defmodule Mix.Tasks.DoneFirst.Baseline do
  @shortdoc "Asks a single model the same gap survey the panel answered"
  @moduledoc """
  The "why not just ask Claude?" control. Gives one model the same stripped
  view and the same two questions as the Flashpoint panel, and prints its
  ratings next to the panel's.

      mix done_first.baseline            # replays cache/baseline.json if present
      mix done_first.baseline --fresh

  Reads `cache/dod_draft.json` and `cache/review.json`. Writes `cache/baseline.json`.
  """
  use Mix.Task

  alias DoneFirst.{Claude, Review}

  @switches [fresh: :boolean, out: :string]

  @system "You are an experienced indie game developer reviewing another developer's definition of done " <>
            "before launch. Answer the survey honestly and concisely."

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    Mix.Task.run("app.start")
    DoneFirst.Dotenv.load()

    out = Keyword.get(opts, :out, "cache/baseline.json")
    review = "cache/review.json" |> File.read!() |> Jason.decode!()

    baseline =
      if File.exists?(out) and not Keyword.get(opts, :fresh, false) do
        IO.puts("Replaying #{out} (pass --fresh to regenerate).")
        out |> File.read!() |> Jason.decode!()
      else
        view =
          "cache/dod_draft.json" |> File.read!() |> Jason.decode!() |> Map.fetch!("panel_view")

        IO.puts("... asking a single model the same survey")

        {:ok, %{data: data}} =
          Claude.json(@system, prompt(view, review["gaps"]), schema(), effort: "medium")

        File.write!(out, Jason.encode_to_iodata!(data, pretty: true))
        data
      end

    print(review, baseline)
  end

  defp prompt(view, gaps) do
    """
    A developer is about to launch the game described below. Judge whether their definition of done is missing anything.

    #{Review.plan_prompt(view)}

    Q1. How important is it to add each of these to the definition of done before launch?
    Answer with exactly one of: #{Enum.join(Review.scale(), ", ")}.
    #{Enum.map_join(gaps, "\n", &"- #{&1}")}

    Q2. What else is missing from this definition of done that would hurt the launch?
    """
  end

  defp schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["grid", "missing"],
      "properties" => %{
        "grid" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["gap", "rating"],
            "properties" => %{
              "gap" => %{"type" => "string"},
              "rating" => %{"type" => "string", "enum" => Review.scale()}
            }
          }
        },
        "missing" => %{"type" => "string"}
      }
    }
  end

  defp print(review, baseline) do
    mine = Map.new(baseline["grid"], &{&1["gap"], &1["rating"]})

    IO.puts("\nPanel (#{review["size"]}) vs single model:")
    IO.puts("  Panel urgent   Model          Gap")

    Enum.each(review["tally"], fn t ->
      urgent = "#{t["urgent"]}/#{t["total"]}"

      IO.puts(
        "  " <>
          String.pad_trailing(urgent, 15) <>
          String.pad_trailing(mine[t["gap"]] || "-", 15) <> t["gap"]
      )
    end)

    IO.puts("\nSingle model, what else is missing:\n" <> baseline["missing"])
  end
end
