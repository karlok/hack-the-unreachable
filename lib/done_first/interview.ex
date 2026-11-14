defmodule DoneFirst.Interview do
  @moduledoc """
  Pure core of the interview loop.

  Each turn the model sees the answers so far and the remaining sections, and
  returns a decision: sections to drop (with reasons), the next question, and
  whether the interview is done. This module builds that prompt, defines the
  decision schema, and applies decisions to the state. No I/O.
  """

  @enforce_keys [:sections]
  defstruct sections: [], transcript: [], dropped: [], turn: 0, max_turns: 8

  @system """
  You are Done First, an interviewer that helps an indie game developer write a definition of done.
  You hold a large question bank grouped into sections. Your job is to ask as few questions as possible
  while learning enough to keep or drop each section.

  Rules:
  - Ask exactly one short, plain-language question per turn. Prefer questions that settle several sections at once
    (platform, engine, online features, languages, monetization, audience, scope).
  - Drop a section only when an answer clearly makes it irrelevant to this game, and cite that answer in the reason.
    Never drop a section on a guess. Never drop core quality sections just because the game is small.
  - Do not re-ask anything already answered.
  - Set done to true when every remaining section is plausibly relevant and further questions would not drop more.
    When done, question must be an empty string.
  """

  def system_prompt, do: @system

  @doc "Starts an interview over `sections` (from `DoneFirst.Bank`)."
  def new(sections, opts \\ []) do
    %__MODULE__{sections: sections, max_turns: Keyword.get(opts, :max_turns, 8)}
  end

  @doc "Sections not yet dropped."
  def remaining(%__MODULE__{sections: sections, dropped: dropped}) do
    gone = MapSet.new(dropped, & &1.key)
    Enum.reject(sections, &MapSet.member?(gone, &1.key))
  end

  @doc "JSON schema for the model's per-turn decision."
  def decision_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["drop", "question", "targets", "done"],
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
        "question" => %{"type" => "string"},
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

    ## Remaining sections (key | label | item count | sample items)
    #{Enum.map_join(remaining(state), "\n", &format_section/1)}

    ## Already dropped
    #{format_dropped(state.dropped)}

    Turn #{state.turn + 1} of at most #{state.max_turns}. Return your decision.
    """
  end

  @doc """
  Applies a decoded decision. Unknown or already-dropped keys are ignored.

  Returns `{:ask, state, question, dropped_now}` or `{:done, state, dropped_now}`.
  Forces `:done` once `max_turns` questions have been asked.
  """
  def apply_decision(%__MODULE__{} = state, %{"drop" => drops} = decision) do
    by_key = Map.new(remaining(state), &{&1.key, &1})

    dropped_now =
      drops
      |> Enum.uniq_by(& &1["section_key"])
      |> Enum.flat_map(fn %{"section_key" => key, "reason" => reason} ->
        case by_key do
          %{^key => section} -> [Map.put(section, :reason, reason)]
          _ -> []
        end
      end)

    state = %{state | dropped: state.dropped ++ dropped_now}
    question = String.trim(decision["question"] || "")

    if decision["done"] or question == "" or state.turn >= state.max_turns do
      {:done, state, dropped_now}
    else
      {:ask, state, question, dropped_now}
    end
  end

  @doc "Records the answer to `question` and advances the turn."
  def record_answer(%__MODULE__{} = state, question, answer) do
    %{state | transcript: state.transcript ++ [%{q: question, a: answer}], turn: state.turn + 1}
  end

  @doc "One line like `dropped 11 questions: Multiplayer (single-player only)`."
  def drop_line([]), do: nil

  def drop_line(dropped) do
    n = DoneFirst.Bank.item_count(dropped)
    "dropped #{n} questions: " <> Enum.map_join(dropped, "; ", &"#{&1.label} (#{&1.reason})")
  end

  @doc "A JSON-friendly summary of the finished interview."
  def to_map(%__MODULE__{} = state) do
    %{
      transcript: state.transcript,
      kept: Enum.map(remaining(state), &Map.take(&1, [:key, :label, :source, :items])),
      dropped: Enum.map(state.dropped, &Map.take(&1, [:key, :label, :source, :reason, :items])),
      kept_items: DoneFirst.Bank.item_count(remaining(state)),
      dropped_items: DoneFirst.Bank.item_count(state.dropped)
    }
  end

  defp format_transcript([]), do: "(none yet)"
  defp format_transcript(t), do: Enum.map_join(t, "\n", &"Q: #{&1.q}\nA: #{&1.a}")

  defp format_dropped([]), do: "(none)"
  defp format_dropped(d), do: Enum.map_join(d, "\n", &"#{&1.key}: #{&1.reason}")

  defp format_section(s) do
    sample = s.items |> Enum.take(3) |> Enum.map_join("; ", &truncate(&1.description))
    "#{s.key} | #{s.label} | #{length(s.items)} | #{sample}"
  end

  defp truncate(text) when byte_size(text) > 90, do: String.slice(text, 0, 87) <> "..."
  defp truncate(text), do: text
end
