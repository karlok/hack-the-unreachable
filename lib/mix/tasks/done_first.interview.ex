defmodule Mix.Tasks.DoneFirst.Interview do
  @shortdoc "Runs the Done First interview loop"
  @moduledoc """
  Interviews the builder and narrows the question bank. Each model call returns
  a batch of two or three questions plus what the last answers let it drop.

      mix done_first.interview                      # you answer in the terminal
      mix done_first.interview --facts priv/demo/roguelite_facts.md
                                                    # a simulated builder answers from a fact sheet
      mix done_first.interview --max-turns 9 --genre roguelite

  Model calls are cached by prompt hash, so a rerun with the same answers
  replays without calling out. Writes the result to `cache/interview_last.json`.
  Set `DONE_FIRST_BACKEND=cli` to skip the API and go straight to `claude -p`.
  """
  use Mix.Task

  alias DoneFirst.{Bank, Cache, Claude, Interview}

  @switches [facts: :string, max_turns: :integer, genre: :string, out: :string]

  @builder_system "You are an indie game developer being interviewed about your game. Answer each " <>
                    "question in one or two casual sentences using only the fact sheet. If the fact " <>
                    "sheet does not say, answer \"not sure yet\"."

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

    facts = if path = opts[:facts], do: File.read!(path)
    {:ok, sections} = Bank.load(genre: Keyword.get(opts, :genre, "roguelite"))
    state = Interview.new(sections, max_turns: Keyword.get(opts, :max_turns, 9))

    IO.puts("Question bank: #{length(sections)} sections, #{Bank.item_count(sections)} items.")
    final = loop(state, facts)

    out = Keyword.get(opts, :out, "cache/interview_last.json")
    summary = Interview.to_map(final)
    File.mkdir_p!(Path.dirname(out))
    File.write!(out, Jason.encode_to_iodata!(summary, pretty: true))

    IO.puts(
      "\nDone after #{final.turn} questions. Kept #{summary.kept_items} items in " <>
        "#{length(summary.kept)} sections, dropped #{summary.dropped_items}. Saved #{out}."
    )
  end

  defp loop(state, facts) do
    IO.puts("\n... choosing next questions")
    prompt = Interview.prompt(state)

    {:ok, %{"data" => decision}, _} =
      Cache.fetch("interview_" <> hash(prompt), fn ->
        Claude.json(Interview.system_prompt(), prompt, Interview.decision_schema(), effort: "low")
      end)

    case Interview.apply_decision(state, decision) do
      {:done, state, dropped} ->
        print_drops(dropped)
        state

      {:ask, state, questions, dropped} ->
        print_drops(dropped)
        answers = ask(questions, facts, state.turn)

        state =
          questions
          |> Enum.zip(answers)
          |> Enum.reduce(state, fn {q, a}, acc -> Interview.record_answer(acc, q, a) end)

        loop(state, facts)
    end
  end

  defp print_drops(dropped) do
    if line = Interview.drop_line(dropped), do: IO.puts("  -> " <> line)
  end

  # Interactive: one prompt per question.
  defp ask(questions, nil, turn) do
    questions
    |> Enum.with_index(turn + 1)
    |> Enum.map(fn {q, n} ->
      IO.puts("\nQ#{n}: #{q}")

      case IO.gets("> ") do
        :eof -> ""
        line -> String.trim(line)
      end
    end)
  end

  # Simulated builder: one call answers the whole batch.
  defp ask(questions, facts, turn) do
    numbered =
      questions |> Enum.with_index(1) |> Enum.map_join("\n", fn {q, i} -> "#{i}. #{q}" end)

    prompt =
      "## Fact sheet\n#{facts}\n\n## Questions\n#{numbered}\n\n" <>
        "Return one answer per question, in order."

    IO.puts("... builder answering")

    {:ok, %{"data" => %{"answers" => answers}}, _} =
      Cache.fetch("builder_" <> hash(prompt), fn ->
        Claude.json(@builder_system, prompt, @answers_schema, effort: "low", max_tokens: 1500)
      end)

    answers = pad(answers, length(questions))

    questions
    |> Enum.zip(answers)
    |> Enum.with_index(turn + 1)
    |> Enum.each(fn {{q, a}, n} -> IO.puts("\nQ#{n}: #{q}\nA: #{a}") end)

    answers
  end

  defp pad(answers, n), do: Enum.take(answers ++ List.duplicate("not sure yet", n), n)

  defp hash(text),
    do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower) |> binary_part(0, 16)
end
