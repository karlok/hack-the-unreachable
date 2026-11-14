defmodule Mix.Tasks.DoneFirst.Interview do
  @shortdoc "Runs the Done First interview loop"
  @moduledoc """
  Interviews the builder and narrows the question bank.

      mix done_first.interview                      # you answer in the terminal
      mix done_first.interview --facts priv/demo/roguelite_facts.md
                                                    # a simulated builder answers from a fact sheet
      mix done_first.interview --max-turns 6 --genre roguelite

  Model decisions are cached by prompt hash, so a rerun with the same answers
  replays without calling out. Writes the result to `cache/interview_last.json`.
  """
  use Mix.Task

  alias DoneFirst.{Bank, Cache, Claude, Interview}

  @switches [facts: :string, max_turns: :integer, genre: :string, out: :string]

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    Mix.Task.run("app.start")
    DoneFirst.Dotenv.load()

    facts = if path = opts[:facts], do: File.read!(path)
    {:ok, sections} = Bank.load(genre: Keyword.get(opts, :genre, "roguelite"))
    state = Interview.new(sections, max_turns: Keyword.get(opts, :max_turns, 8))

    IO.puts("Question bank: #{length(sections)} sections, #{Bank.item_count(sections)} items.\n")
    final = loop(state, facts)

    out = Keyword.get(opts, :out, "cache/interview_last.json")
    File.mkdir_p!(Path.dirname(out))
    File.write!(out, Jason.encode_to_iodata!(Interview.to_map(final), pretty: true))

    summary = Interview.to_map(final)

    IO.puts(
      "\nDone after #{final.turn} questions. Kept #{summary.kept_items} items in " <>
        "#{length(summary.kept)} sections, dropped #{summary.dropped_items}. Saved #{out}."
    )
  end

  defp loop(state, facts) do
    prompt = Interview.prompt(state)

    {:ok, %{"data" => decision}, _} =
      Cache.fetch("interview_" <> hash(prompt), fn ->
        Claude.json(Interview.system_prompt(), prompt, Interview.decision_schema(), effort: "low")
      end)

    case Interview.apply_decision(state, decision) do
      {:done, state, dropped} ->
        print_drops(dropped)
        state

      {:ask, state, question, dropped} ->
        print_drops(dropped)
        IO.puts("\nQ#{state.turn + 1}: #{question}")
        answer = answer(question, facts, state)
        if facts, do: IO.puts("A: #{answer}")
        loop(Interview.record_answer(state, question, answer), facts)
    end
  end

  defp print_drops(dropped) do
    if line = Interview.drop_line(dropped), do: IO.puts("  -> " <> line)
  end

  defp answer(_question, nil, _state) do
    case IO.gets("> ") do
      :eof -> ""
      line -> String.trim(line)
    end
  end

  defp answer(question, facts, state) do
    system =
      "You are an indie game developer being interviewed about your game. Answer in one or two " <>
        "casual sentences using only the fact sheet. If the fact sheet does not say, answer \"not sure yet\"."

    prompt = "## Fact sheet\n#{facts}\n\n## Question\n#{question}"

    {:ok, %{"text" => text}, _} =
      Cache.fetch("builder_" <> hash(prompt <> "#{state.turn}"), fn ->
        Claude.text(system, prompt, effort: "low", max_tokens: 400)
      end)

    String.trim(text)
  end

  defp hash(text),
    do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower) |> binary_part(0, 16)
end
