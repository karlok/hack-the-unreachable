defmodule Mix.Tasks.DoneFirst.Draft do
  @shortdoc "Drafts the DoD from the interview and strips it for the panel"
  @moduledoc """
  Reads the interview result, writes tailored DoD items with a stripped twin
  for each, prints them side by side, and checks the stripped text for leaks.

      mix done_first.draft
      mix done_first.draft --notes priv/demo/roguelite_facts.md --in cache/interview_last.json

  `--notes` is the builder's own pitch (optional). Writes `cache/dod_draft.json`,
  including `panel_view`, the compact stripped view the gap review sends to the panel.
  A rerun replays the saved file; pass `--fresh` to regenerate.
  """
  use Mix.Task

  alias DoneFirst.{Cache, Claude, Draft}

  @switches [in: :string, out: :string, notes: :string, fresh: :boolean]

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    Mix.Task.run("app.start")
    DoneFirst.Dotenv.load()

    out = Keyword.get(opts, :out, "cache/dod_draft.json")

    {draft, source} =
      if File.exists?(out) and not Keyword.get(opts, :fresh, false) do
        IO.puts("Replaying #{out} (pass --fresh to regenerate).")
        {out |> File.read!() |> Jason.decode!(), :cached}
      else
        generate(opts)
      end

    interview = %{"kept_items" => draft["kept_items"]}

    generic = interview["kept_items"]
    tailored = length(draft["tailored"])

    IO.puts(
      "Draft: #{generic} generic items kept from the bank + #{tailored} tailored items (#{source}).\n"
    )

    IO.puts(Draft.rule() <> "\n")
    IO.puts(Draft.side_by_side(Draft.changed(draft)))

    IO.puts("\nWhat left: " <> Enum.join(Draft.removed_terms(draft), ", "))

    case Draft.leaks(draft) do
      [] ->
        IO.puts("Leak check (by code): 0 removed terms reach the panel.")

      leaks ->
        IO.puts("Leak check: #{length(leaks)} LEAK(S)")
        Enum.each(leaks, &IO.puts("  \"#{&1.term}\" in: #{&1.stripped}"))
    end

    if source != :cached do
      File.write!(out, Jason.encode_to_iodata!(draft, pretty: true))
      IO.puts("Saved #{out}.")
    end
  end

  defp generate(opts) do
    interview =
      opts
      |> Keyword.get(:in, "cache/interview_last.json")
      |> File.read!()
      |> Jason.decode!()

    notes = if path = opts[:notes], do: File.read!(path)
    prompt = Draft.prompt(interview, notes)
    IO.puts("... drafting the definition of done")

    {:ok, %{"data" => draft}, source} =
      Cache.fetch("draft_" <> hash(Draft.system_prompt() <> prompt), fn ->
        Claude.json(Draft.system_prompt(), prompt, Draft.schema(), effort: "medium")
      end)

    record =
      Map.merge(draft, %{
        "kept" => interview["kept"],
        "kept_items" => interview["kept_items"],
        "transcript" => interview["transcript"],
        "panel_view" => Draft.panel_view(draft, interview["kept"])
      })

    {record, source}
  end

  defp hash(text),
    do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower) |> binary_part(0, 16)
end
