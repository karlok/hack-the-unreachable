defmodule DoneFirst.CircleBack do
  @moduledoc """
  Pure core of the circle-back step.

  1. `triage_*`: cluster the panel's open answers into distinct catches, check
     each against the full DoD, and note whether the single-model baseline
     raised it too.
  2. The builder answers only the uncovered catches.
  3. `final_*`: turn each answer into DoD items, then render the final DoD with
     a trail of what the panel caught. No I/O.
  """

  @triage_system """
  You are Done First. A panel of practitioners reviewed a stripped definition of done (DoD) and said, in their own
  words, what is missing. Group their answers into distinct catches (one concrete risk each, 6 to 12 catches).

  For each catch:
  - respondents: the numbers of every respondent who raised it (count carefully; only include a respondent if their
    answer clearly names this risk).
  - covered_by: if the full DoD below already has an item that clearly covers it, quote that item's text;
    otherwise "". Be strict: a vague or partial item does not count as covered.
  - baseline_raised: true if the single-model answer below also names this risk.
  - question: one short, plain question to ask the builder so the gap can be closed (only matters when not covered).
  """

  def triage_system, do: @triage_system

  def triage_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["catches"],
      "properties" => %{
        "catches" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["title", "respondents", "covered_by", "baseline_raised", "question"],
            "properties" => %{
              "title" => %{"type" => "string"},
              "respondents" => %{"type" => "array", "items" => %{"type" => "integer"}},
              "covered_by" => %{"type" => "string"},
              "baseline_raised" => %{"type" => "boolean"},
              "question" => %{"type" => "string"}
            }
          }
        }
      }
    }
  end

  @doc "Triage prompt from the draft (full DoD), the review and the baseline."
  def triage_prompt(draft, review, baseline) do
    respondents =
      review["flashpoint"]["respondents"]
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {r, i} -> "#{i}. [#{r["occupation"]}] #{r["missing"]}" end)

    """
    ## Panel answers to "What else is missing from this definition of done?"
    #{respondents}

    ## Single-model answer to the same question
    #{baseline["missing"]}

    ## Full DoD: specific items
    #{Enum.map_join(draft["tailored"], "\n", &"- #{&1["draft"]}")}

    ## Full DoD: candidate gaps already added after panel rating
    #{Enum.map_join(review["gaps"], "\n", &"- #{&1}")}

    ## Full DoD: generic items by section
    #{Enum.map_join(draft["kept"], "\n", &format_section/1)}
    """
  end

  @doc """
  Normalizes triaged catches: drops respondent numbers outside `1..n`,
  dedupes them, and sorts by mention count. Adds `count` and `covered`.
  """
  def normalize(catches, n) do
    catches
    |> Enum.map(fn c ->
      rs = c["respondents"] |> Enum.filter(&(&1 in 1..n)) |> Enum.uniq() |> Enum.sort()

      Map.merge(c, %{
        "respondents" => rs,
        "count" => length(rs),
        "covered" => c["covered_by"] != ""
      })
    end)
    |> Enum.reject(&(&1["count"] == 0))
    |> Enum.sort_by(&(-&1["count"]))
  end

  def open_gaps(catches), do: Enum.reject(catches, & &1["covered"])

  @final_system """
  You are Done First. For each gap the panel caught, write one or two DoD items: concrete, checkable "done when"
  statements that use the builder's answer. If the builder is unsure, write the item as a decision that must be
  made before launch, with the options named. Keep each item to one sentence.
  """

  def final_system, do: @final_system

  def final_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["items"],
      "properties" => %{
        "items" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["gap", "text"],
            "properties" => %{"gap" => %{"type" => "string"}, "text" => %{"type" => "string"}}
          }
        }
      }
    }
  end

  def final_prompt(answered) do
    Enum.map_join(answered, "\n\n", fn a ->
      "Gap: #{a["title"]}\nQ: #{a["question"]}\nBuilder: #{a["answer"]}"
    end)
  end

  @doc """
  Labels each catch by where it stands, in code, by exact match:
  `"new"` (in neither the draft nor the rated candidates: raised unprompted),
  `"candidate"` (repeats a row the panel was shown in the grid, so it is primed),
  or `"draft"` (the builder's draft already had it).
  """
  def classify(catches, candidates) do
    set = MapSet.new(candidates)

    Enum.map(catches, fn c ->
      kind =
        cond do
          not c["covered"] -> "new"
          MapSet.member?(set, c["covered_by"]) -> "candidate"
          true -> "draft"
        end

      Map.put(c, "kind", kind)
    end)
  end

  @doc "Catches grouped for display: new first, then candidate echoes, then draft."
  def ordered(catches) do
    rank = %{"new" => 0, "candidate" => 1, "draft" => 2}
    Enum.sort_by(catches, &{rank[&1["kind"]], -&1["count"]})
  end

  @doc "One trail line per catch. The baseline comparison is shown only for new catches, where it is a fair test."
  def trail_line(c, n) do
    status =
      case c["kind"] do
        "new" -> "NEW, raised unprompted"
        "candidate" -> "echoes a rated candidate"
        "draft" -> "already in draft"
        nil -> if c["covered"], do: "already covered", else: "NEW"
      end

    also =
      cond do
        c["kind"] not in ["new", nil] -> ""
        c["baseline_raised"] -> ", single model also raised it"
        true -> ", single model missed it"
      end

    "[#{c["count"]}/#{n}] #{c["title"]} (#{status}#{also})"
  end

  @doc "Final DoD as Markdown: trail first, then new items, then the rest."
  def markdown(draft, review, catches, items, n) do
    catches = catches |> classify(review["gaps"]) |> ordered()
    new_items = Enum.group_by(items, & &1["gap"], & &1["text"])

    """
    # Definition of done

    #{review["routing_label"]}: #{n} panelists reviewed the stripped draft.
    NEW means the panel raised it unprompted: it was in neither the draft nor the rows they rated.

    ## What the panel caught

    #{Enum.map_join(catches, "\n", &("- " <> trail_line(&1, n)))}

    ## Added after the panel review

    #{Enum.map_join(new_items, "\n", fn {gap, texts} -> "**#{gap}**\n" <> Enum.map_join(texts, "\n", &"- [ ] #{&1}") <> "\n" end)}
    ## Rated by the panel

    #{Enum.map_join(review["gaps"], "\n", &"- [ ] #{&1}")}

    ## Specific to this game

    #{Enum.map_join(draft["tailored"], "\n", &"- [ ] #{&1["draft"]}")}

    ## General checklist

    #{Enum.map_join(draft["kept"], "\n", fn s -> "### #{s["label"]}\n" <> Enum.map_join(s["items"], "\n", &"- [ ] #{&1["description"]}") <> "\n" end)}
    """
  end

  defp format_section(s) do
    "- #{s["label"]}: " <> Enum.map_join(s["items"], "; ", &short(&1["description"]))
  end

  defp short(text) when byte_size(text) > 90, do: String.slice(text, 0, 87) <> "..."
  defp short(text), do: text
end
