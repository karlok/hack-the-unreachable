defmodule DoneFirst.Interview do
  @moduledoc """
  Pure core of the interview loop.

  Each turn the model sees the answers so far and the remaining sections, and
  returns a decision: sections to drop (with reasons), the next question, and
  whether the interview is done. This module builds that prompt, defines the
  decision schema, and applies decisions to the state. No I/O.
  """

  @enforce_keys [:sections]
  defstruct sections: [], transcript: [], dropped: [], dropped_items: [], turn: 0, max_turns: 9

  @system """
  You are Done First, an interviewer that helps an indie game developer write a definition of done.
  You hold a large question bank grouped into sections. Your job is to ask as few questions as possible
  while learning enough to keep or drop each section.

  Rules:
  - Ask two or three short, plain-language questions per turn (the builder answers them together). Prefer
    questions that settle many items at once, and do not ask about the same topic twice in one batch.
  - After every answer, drop everything it makes irrelevant: whole sections (drop) when the whole section no longer
    applies, and individual items (drop_items, using "section_key/item_key") when only some do. Examples: English
    only drops translation and locale items; no console or Steam drops certification, achievements and storefront
    items; no voice acting drops VO items; local saves only drops cloud-save items.
  - Cite the builder's answer in every reason. Never drop on a guess. Keep core quality items that still apply.
  - Do not re-ask anything already answered.
  - Cover these topics before finishing, unless already answered: platform and stores, engine, online features,
    languages, input devices, save data, monetization and payments, story, voice and cutscenes, accessibility goals,
    team size and timeline.
  - Set done to true only when further questions would not drop anything. When done, questions must be [].
  """

  def system_prompt, do: @system

  @doc "Starts an interview over `sections` (from `DoneFirst.Bank`)."
  def new(sections, opts \\ []) do
    %__MODULE__{sections: sections, max_turns: Keyword.get(opts, :max_turns, 8)}
  end

  @doc "Sections not yet dropped, with dropped items removed. Empty sections are left out."
  def remaining(%__MODULE__{sections: sections, dropped: dropped, dropped_items: items}) do
    gone = MapSet.new(dropped, & &1.key)
    gone_items = MapSet.new(items, &{&1.section_key, &1.key})

    sections
    |> Enum.reject(&MapSet.member?(gone, &1.key))
    |> Enum.map(fn s ->
      %{s | items: Enum.reject(s.items, &MapSet.member?(gone_items, {s.key, &1.key}))}
    end)
    |> Enum.reject(&(&1.items == []))
  end

  @doc "JSON schema for the model's per-turn decision."
  def decision_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["drop", "drop_items", "questions", "targets", "done"],
      "properties" => %{
        "drop" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["section_key", "reason"],
            "properties" => %{
              "section_key" => %{"type" => "string"},
              "reason" => %{"type" => "string"}
            }
          }
        },
        "drop_items" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["item", "reason"],
            "properties" => %{
              "item" => %{"type" => "string", "description" => "section_key/item_key"},
              "reason" => %{"type" => "string"}
            }
          }
        },
        "questions" => %{"type" => "array", "items" => %{"type" => "string"}},
        "targets" => %{"type" => "array", "items" => %{"type" => "string"}},
        "done" => %{"type" => "boolean"}
      }
    }
  end

  @doc "The user prompt for the next decision."
  def prompt(%__MODULE__{} = state) do
    """
    ## Answers so far
    #{format_transcript(state.transcript)}

    ## Remaining sections and items (section_key/item_key: description)
    #{Enum.map_join(remaining(state), "\n\n", &format_section/1)}

    ## Already dropped
    #{format_dropped(state.dropped)}

    #{state.turn} questions asked so far, at most #{state.max_turns} in total. Return your decision.
    """
  end

  @doc """
  Applies a decoded decision. Unknown or already-dropped keys are ignored.

  `dropped_now` is a list of `%{label, count}` per section, for display.
  Returns `{:ask, state, questions, dropped_now}` or `{:done, state, dropped_now}`.
  Questions are capped so the total never exceeds `max_turns`.
  """
  def apply_decision(%__MODULE__{} = state, %{"drop" => drops} = decision) do
    live = remaining(state)
    by_key = Map.new(live, &{&1.key, &1})

    dropped_now =
      drops
      |> Enum.uniq_by(& &1["section_key"])
      |> Enum.flat_map(fn %{"section_key" => key, "reason" => reason} ->
        case by_key do
          %{^key => section} -> [Map.put(section, :reason, reason)]
          _ -> []
        end
      end)

    section_keys = MapSet.new(dropped_now, & &1.key)

    items_now =
      (decision["drop_items"] || [])
      |> Enum.flat_map(&lookup_item(&1, by_key, section_keys))
      |> Enum.uniq_by(&{&1.section_key, &1.key})

    state = %{
      state
      | dropped: state.dropped ++ dropped_now,
        dropped_items: state.dropped_items ++ items_now
    }

    shown =
      Enum.map(dropped_now, &%{label: &1.label, count: length(&1.items)}) ++
        group_items(items_now)

    questions =
      (decision["questions"] || [])
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(max(state.max_turns - state.turn, 0))

    if decision["done"] or questions == [] do
      {:done, state, shown}
    else
      {:ask, state, questions, shown}
    end
  end

  defp lookup_item(%{"item" => ref, "reason" => reason}, by_key, section_keys) do
    with [skey, ikey] <- String.split(ref, "/", parts: 2),
         false <- MapSet.member?(section_keys, skey),
         %{items: items, label: label} <- Map.get(by_key, skey),
         %{} = item <- Enum.find(items, &(&1.key == ikey)) do
      [Map.merge(item, %{section_key: skey, section_label: label, reason: reason})]
    else
      _ -> []
    end
  end

  defp group_items(items) do
    items
    |> Enum.group_by(& &1.section_label)
    |> Enum.map(fn {label, group} -> %{label: label, count: length(group)} end)
  end

  @doc "Records the answer to `question` and advances the turn."
  def record_answer(%__MODULE__{} = state, question, answer) do
    %{state | transcript: state.transcript ++ [%{q: question, a: answer}], turn: state.turn + 1}
  end

  @doc "One line like `dropped 13 questions: Multiplayer & Online Features (11), Settings Menu (2)`."
  def drop_line([]), do: nil

  def drop_line(dropped) do
    merged =
      dropped
      |> Enum.group_by(& &1.label, & &1.count)
      |> Enum.map(fn {label, counts} -> {label, Enum.sum(counts)} end)
      |> Enum.sort_by(fn {_, n} -> -n end)

    n = Enum.reduce(merged, 0, fn {_, c}, acc -> acc + c end)
    noun = if n == 1, do: "question", else: "questions"

    "dropped #{n} #{noun}: " <>
      Enum.map_join(merged, ", ", fn {label, c} -> "#{label} (#{c})" end)
  end

  @doc "A JSON-friendly summary of the finished interview."
  def to_map(%__MODULE__{} = state) do
    %{
      transcript: state.transcript,
      kept: Enum.map(remaining(state), &Map.take(&1, [:key, :label, :source, :items])),
      dropped: Enum.map(state.dropped, &Map.take(&1, [:key, :label, :source, :reason, :items])),
      dropped_single_items: state.dropped_items,
      kept_items: DoneFirst.Bank.item_count(remaining(state)),
      dropped_items: DoneFirst.Bank.item_count(state.dropped) + length(state.dropped_items)
    }
  end

  defp format_transcript([]), do: "(none yet)"
  defp format_transcript(t), do: Enum.map_join(t, "\n", &"Q: #{&1.q}\nA: #{&1.a}")

  defp format_dropped([]), do: "(none)"
  defp format_dropped(d), do: Enum.map_join(d, "\n", &"#{&1.key}: #{&1.reason}")

  defp format_section(s) do
    items = Enum.map_join(s.items, "\n", &"- #{s.key}/#{&1.key}: #{truncate(&1.description)}")
    "### #{s.key} (#{s.label})\n#{items}"
  end

  defp truncate(text) when byte_size(text) > 120, do: String.slice(text, 0, 117) <> "..."
  defp truncate(text), do: text
end
