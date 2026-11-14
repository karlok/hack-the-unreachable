defmodule DoneFirst.Draft do
  @moduledoc """
  Pure core of the DoD draft and the stripping rule.

  The draft is the kept bank items (already generic) plus tailored items the
  model writes from the interview. Each tailored item comes with a stripped
  version for the panel and the terms that were removed. `leaks/2` checks the
  stripped text deterministically, so the theft-proofing claim does not rest on
  the model's word alone. No I/O.
  """

  @rule """
  Stripping rule: nouns, names, story and specific mechanics come out; \
  constraints, interfaces, formats and budgets stay in.\
  """

  def rule, do: @rule

  # Technical phrases that contain an ordinary word the game may also use as a
  # name (e.g. a level called "the final depth"). Skipped by the leak scan.
  @technical [
    "depth sorting",
    "depth buffer",
    "depth test",
    "depth of field",
    "level geometry",
    "level of detail"
  ]

  def technical_phrases, do: @technical

  @system """
  You are Done First. You write a definition of done (DoD) for an indie game from an interview, then strip it
  so it can be shown to outside experts without leaking the game's concept.

  1. Write 25 to 40 tailored DoD items. Each is one concrete, checkable "done when" statement that uses what the
     builder said: platform, engine, payment, input, saves, scope, timeline, genre loop. Do not repeat generic
     bank items that are already listed; add the specifics the bank cannot know. Where the builder was unsure,
     write the item as a decision that must be made (e.g. "Decided whether runs can be resumed mid-way").
  2. For each item write a stripped version by applying this rule:
     #{@rule}
     Remove: the game's title, character/place/item names, story, setting, art direction, and any mechanic
     specific enough to identify the game. Keep: platforms, engines, APIs, file formats, payment providers,
     performance and size budgets, input devices, team size and timeline, and generic genre structure
     (e.g. "runs", "meta-progression").
     Edge cases, decided:
     - Interfaces and providers stay: "Stripe", "Paddle", "BabylonJS", "Gamepad API", "localStorage", "gamepad".
     - Specific mechanics and setting become generic structure: "procedurally generated caverns" becomes
       "procedurally generated levels"; "top-down combat" becomes "combat"; "lore notes" becomes "in-game text".
     - Exact prices go: "$8" becomes "single low-price purchase". List the figure in removed.
     - Art direction goes: "pixel-art sprites on low-poly levels" becomes "sprite and 3D assets".
  3. In removed, list the exact words or phrases you took out of that item (empty if none).
  """

  def system_prompt, do: @system

  @doc "JSON schema for the draft response."
  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["game_title", "protected_terms", "tailored"],
      "properties" => %{
        "game_title" => %{"type" => "string"},
        "protected_terms" => %{
          "type" => "array",
          "description" => "Every concept-identifying term in the interview and notes",
          "items" => %{"type" => "string"}
        },
        "tailored" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["section_key", "draft", "stripped", "removed"],
            "properties" => %{
              "section_key" => %{"type" => "string"},
              "draft" => %{"type" => "string"},
              "stripped" => %{"type" => "string"},
              "removed" => %{"type" => "array", "items" => %{"type" => "string"}}
            }
          }
        }
      }
    }
  end

  @doc "The user prompt, from the interview summary map (`cache/interview_last.json`) and optional notes."
  def prompt(interview, notes \\ nil) do
    """
    ## Builder's notes
    #{notes || "(none)"}

    ## Interview
    #{Enum.map_join(interview["transcript"], "\n", &"Q: #{&1["q"]}\nA: #{&1["a"]}")}

    ## Sections and generic items already in the DoD (do not repeat these)
    #{Enum.map_join(interview["kept"], "\n", &format_section/1)}
    """
  end

  @doc """
  Returns the terms that still appear in stripped text: the title, the
  protected terms, and every item's removed terms. Case-insensitive, whole words.
  """
  def leaks(%{"tailored" => items} = draft) do
    terms =
      ([draft["game_title"]] ++
         (draft["protected_terms"] || []) ++ Enum.flat_map(items, & &1["removed"]))
      |> Enum.reject(&(is_nil(&1) or String.length(String.trim(&1)) < 3))
      |> Enum.uniq_by(&String.downcase/1)

    for item <- items, term <- terms, mentions?(item["stripped"], term), uniq: true do
      %{term: term, stripped: item["stripped"]}
    end
  end

  @doc "All distinct removed terms, in first-seen order."
  def removed_terms(%{"tailored" => items}) do
    items |> Enum.flat_map(& &1["removed"]) |> Enum.uniq_by(&String.downcase/1)
  end

  @doc """
  The compact view the panel sees: stripped tailored items plus the headings
  of the kept bank sections (the panel is asked what is missing, not to read
  every generic item).
  """
  def panel_view(%{"tailored" => items}, kept) do
    %{
      "rule" => @rule,
      "sections_covered" => Enum.map(kept, &"#{&1["label"]} (#{length(&1["items"])} items)"),
      "specific_items" => Enum.map(items, & &1["stripped"])
    }
  end

  @doc "Rows that changed under stripping, as `{draft, stripped}`."
  def changed(%{"tailored" => items}) do
    for %{"draft" => d, "stripped" => s} <- items, d != s, do: {d, s}
  end

  @doc "Renders `{left, right}` rows as two wrapped columns of `width` each."
  def side_by_side(rows, width \\ 38) do
    header = pad("DRAFT (builder sees)", width) <> " | " <> "STRIPPED (panel sees)"
    rule = String.duplicate("-", width) <> "-+-" <> String.duplicate("-", width)

    body =
      Enum.map_join(rows, "\n" <> rule <> "\n", fn {l, r} ->
        ls = wrap(l, width)
        rs = wrap(r, width)
        n = max(length(ls), length(rs))

        Enum.map_join(0..(n - 1), "\n", fn i ->
          pad(Enum.at(ls, i, ""), width) <> " | " <> Enum.at(rs, i, "")
        end)
      end)

    Enum.join([header, rule, body], "\n")
  end

  @doc "Greedy word wrap to `width` characters."
  def wrap(text, width) do
    text
    |> String.split()
    |> Enum.reduce([], fn
      word, [] ->
        [word]

      word, [line | rest] ->
        if String.length(line) + 1 + String.length(word) <= width,
          do: [line <> " " <> word | rest],
          else: [word, line | rest]
    end)
    |> Enum.reverse()
  end

  defp pad(s, width), do: String.pad_trailing(s, width)

  defp mentions?(text, term) do
    text = Enum.reduce(@technical, text, &String.replace(&2, ~r/#{Regex.escape(&1)}/iu, " "))
    Regex.match?(~r/(?<![\w])#{Regex.escape(term)}(?![\w])/iu, text)
  end

  defp format_section(s) do
    items = Enum.map_join(s["items"], "; ", &short(&1["description"]))
    "- #{s["key"]} (#{s["label"]}): #{items}"
  end

  defp short(text) when byte_size(text) > 70, do: String.slice(text, 0, 67) <> "..."
  defp short(text), do: text
end
