defmodule Mix.Tasks.DoneFirst.CircleBack do
  @shortdoc "Folds the panel's catches back into the DoD"
  @moduledoc """
  Groups the panel's open answers into catches, checks them against the DoD,
  asks the builder only about the gaps, and writes the final DoD with a trail.

      mix done_first.circle_back                    # replays cache/final_dod.json if present
      mix done_first.circle_back --fresh            # you answer the gap questions
      mix done_first.circle_back --fresh --facts priv/demo/roguelite_facts.md

  Reads `cache/dod_draft.json`, `cache/review.json`, `cache/baseline.json`.
  Writes `cache/final_dod.json` and `cache/final_dod.md`.
  """
  use Mix.Task

  alias DoneFirst.{Claude, CircleBack}

  @switches [fresh: :boolean, facts: :string]

  @builder_system "You are an indie game developer. Answer each question in one or two casual sentences " <>
                    "using only the fact sheet. If the fact sheet does not say, answer \"not sure yet\"."

  @answers_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["answers"],
    "properties" => %{"answers" => %{"type" => "array", "items" => %{"type" => "string"}}}
  }

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    Mix.Task.run("app.start")
    DoneFirst.Dotenv.load()

    out = "cache/final_dod.json"

    result =
      if File.exists?(out) and not Keyword.get(opts, :fresh, false) do
        IO.puts("Replaying #{out} (pass --fresh to redo).")
        result = out |> File.read!() |> Jason.decode!()
        # Re-render from saved data so display fixes apply without new model calls.
        md =
          CircleBack.markdown(
            read("cache/dod_draft.json"),
            read("cache/review.json"),
            result["catches"],
            result["items"],
            result["n"]
          )

        File.write!("cache/final_dod.md", md)
        result
      else
        result = live(opts)
        File.write!(out, Jason.encode_to_iodata!(result, pretty: true))
        File.write!("cache/final_dod.md", result["markdown"])
        result
      end

    print(result)
  end

  defp live(opts) do
    draft = read("cache/dod_draft.json")
    review = read("cache/review.json")
    baseline = read("cache/baseline.json")
    n = length(review["flashpoint"]["respondents"])

    IO.puts("... grouping the panel's answers and checking them against the DoD")

    {:ok, %{data: %{"catches" => raw}}} =
      Claude.json(
        CircleBack.triage_system(),
        CircleBack.triage_prompt(draft, review, baseline),
        CircleBack.triage_schema(),
        effort: "medium"
      )

    catches = CircleBack.normalize(raw, n)
    gaps = CircleBack.open_gaps(catches)

    IO.puts(
      "#{length(catches)} catches, #{length(gaps)} not covered by the DoD. Asking the builder about those only."
    )

    answers = ask(Enum.map(gaps, & &1["question"]), opts[:facts])
    answered = gaps |> Enum.zip(answers) |> Enum.map(fn {g, a} -> Map.put(g, "answer", a) end)

    IO.puts("... writing the new DoD items")

    {:ok, %{data: %{"items" => items}}} =
      Claude.json(
        CircleBack.final_system(),
        CircleBack.final_prompt(answered),
        CircleBack.final_schema(),
        effort: "medium"
      )

    %{
      "n" => n,
      "catches" => catches,
      "answered" => answered,
      "items" => items,
      "markdown" => CircleBack.markdown(draft, review, catches, items, n)
    }
  end

  defp ask(questions, nil) do
    Enum.map(questions, fn q ->
      IO.puts("\n#{q}")

      case IO.gets("> ") do
        :eof -> ""
        line -> String.trim(line)
      end
    end)
  end

  defp ask(questions, facts_path) do
    numbered =
      questions |> Enum.with_index(1) |> Enum.map_join("\n", fn {q, i} -> "#{i}. #{q}" end)

    prompt =
      "## Fact sheet\n#{File.read!(facts_path)}\n\n## Questions\n#{numbered}\n\nOne answer per question, in order."

    {:ok, %{data: %{"answers" => answers}}} =
      Claude.json(@builder_system, prompt, @answers_schema, effort: "low", max_tokens: 2000)

    Enum.take(answers ++ List.duplicate("not sure yet", length(questions)), length(questions))
  end

  defp print(%{"n" => n, "catches" => catches, "answered" => answered, "items" => items}) do
    candidates = read("cache/review.json")["gaps"]
    catches = catches |> CircleBack.classify(candidates) |> CircleBack.ordered()
    new = Enum.count(catches, &(&1["kind"] == "new"))

    IO.puts("\nWhat the panel caught (#{new} new, raised unprompted):")
    Enum.each(catches, &IO.puts("  " <> CircleBack.trail_line(&1, n)))

    IO.puts("\nBack to the builder (gaps only):")
    Enum.each(answered, &IO.puts("  Q: #{&1["question"]}\n  A: #{&1["answer"]}"))

    IO.puts("\nAdded to the definition of done:")
    Enum.each(items, &IO.puts("  - [ ] #{&1["text"]}"))
    IO.puts("\nSaved cache/final_dod.json and cache/final_dod.md.")
  end

  defp read(path), do: path |> File.read!() |> Jason.decode!()
end
