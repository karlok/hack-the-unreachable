defmodule Mix.Tasks.DoneFirst.Review do
  @shortdoc "Routes the stripped DoD to a Flashpoint panel and tallies the gaps"
  @moduledoc """
  Reads `panel_view` from `cache/dod_draft.json`, plans the routing and the
  candidate gaps, runs the Flashpoint gap survey, and prints the ranked gaps
  plus the panel's open answers.

      mix done_first.review                 # replays cache/review.json if present
      mix done_first.review --fresh         # new plan and a new live panel run
      mix done_first.review --size 12
      mix done_first.review --survey-id S --panel-id P --run-id R
                                            # skip the run, fetch rows of a finished one

  Writes `cache/review.json`.
  """
  use Mix.Task

  alias DoneFirst.{Cache, Claude, Panel, Review}

  @switches [
    in: :string,
    out: :string,
    size: :integer,
    fresh: :boolean,
    survey_id: :string,
    panel_id: :string,
    run_id: :string
  ]

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    Mix.Task.run("app.start")
    DoneFirst.Dotenv.load()

    out = Keyword.get(opts, :out, "cache/review.json")

    review =
      if File.exists?(out) and not Keyword.get(opts, :fresh, false) do
        IO.puts("Replaying #{out} (pass --fresh for a new live panel run).")
        out |> File.read!() |> Jason.decode!()
      else
        review = live(opts)

        if review["flashpoint"]["respondents"] == [] do
          for e <- review["flashpoint"]["errors"] || [], do: IO.puts("note: " <> e)
          Mix.raise("No responses came back, so nothing was saved. See notes above.")
        end

        File.write!(out, Jason.encode_to_iodata!(review, pretty: true))
        review
      end

    print(review)
    IO.puts("\nSaved #{out}.")
  end

  defp live(opts) do
    n = Keyword.get(opts, :size, 12)
    draft = opts |> Keyword.get(:in, "cache/dod_draft.json") |> File.read!() |> Jason.decode!()
    view = draft["panel_view"]
    fresh = Keyword.get(opts, :fresh, false)

    IO.puts("... choosing who should review this definition of done")
    prompt = Review.plan_prompt(view)

    {:ok, %{"data" => plan}, _} =
      Cache.fetch("plan_" <> hash(Review.plan_system() <> prompt), fn ->
        Claude.json(Review.plan_system(), prompt, Review.plan_schema(), effort: "medium")
      end)

    IO.puts(Review.routing_line(plan["routing_label"], n))
    call = if fresh, do: &Panel.call_live/3, else: &Panel.call/3
    t0 = System.monotonic_time(:millisecond)

    ids =
      if opts[:survey_id] && opts[:panel_id] && opts[:run_id] do
        IO.puts("... resuming finished run #{opts[:run_id]}")

        %{
          "survey_id" => opts[:survey_id],
          "panel_id" => opts[:panel_id],
          "run_id" => opts[:run_id]
        }
      else
        IO.puts("... building the gap survey and running the panel (a few minutes)")
        run_prompt = Review.flashpoint_prompt(plan, view, n)

        {:ok, env, _} =
          call.("review_run_" <> hash(run_prompt), run_prompt, schema: Review.run_schema())

        ids = output(env)
        for e <- ids["errors"] || [], do: IO.puts("note: " <> e)

        if ids["run_id"] in [nil, ""],
          do:
            Mix.raise(
              "The panel run did not finish. Resume with --survey-id/--panel-id/--run-id."
            )

        IO.puts(
          "... panel done: survey #{ids["survey_id"]}, panel #{ids["panel_id"]}, run #{ids["run_id"]}"
        )

        ids
      end

    IO.puts("... fetching the panel's answers")
    fetch_prompt = Review.fetch_prompt(ids, plan["gaps"])

    {:ok, envelope, source} =
      call.("review_rows_" <> hash(fetch_prompt), fetch_prompt,
        schema: Review.flashpoint_schema()
      )

    secs = div(System.monotonic_time(:millisecond) - t0, 1000)
    result = output(envelope)

    %{
      "routing_label" => plan["routing_label"],
      "research_objective" => plan["research_objective"],
      "size" => n,
      "gaps" => plan["gaps"],
      "flashpoint" => result,
      "tally" => Review.tally(plan["gaps"], result["respondents"]),
      "panel_seconds" => secs,
      "panel_source" => to_string(source),
      "panel_cost_usd" => envelope["total_cost_usd"]
    }
  end

  defp print(review) do
    respondents = review["flashpoint"]["respondents"]
    IO.puts("\n" <> Review.routing_line(review["routing_label"], review["size"]))
    IO.puts("#{length(respondents)} responses. Occupations: " <> occupations(respondents))
    IO.puts("\nGap review (sorted by Critical + Important):")
    IO.puts(review["tally"] |> Enum.map(&atomize/1) |> Review.table())
    IO.puts("\nWhat else is missing, in the panel's words:")
    Enum.each(respondents, &IO.puts("- [#{&1["occupation"]}] #{&1["missing"]}"))

    for e <- review["flashpoint"]["errors"] || [], do: IO.puts("note: " <> e)
  end

  defp output(env), do: env["structured_output"] || Jason.decode!(env["result"])

  defp occupations(rs),
    do:
      rs
      |> Enum.frequencies_by(& &1["occupation"])
      |> Enum.map_join("; ", fn {o, c} -> "#{o} x#{c}" end)

  defp atomize(%{"gap" => g, "counts" => c}), do: %{gap: g, counts: c}
  defp atomize(%{gap: _} = t), do: t

  defp hash(text),
    do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower) |> binary_part(0, 16)
end
