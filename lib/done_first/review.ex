defmodule DoneFirst.Review do
  @moduledoc """
  Pure core of the panel gap review.

  1. `plan_*`: one model call turns the stripped panel view into a routing spec
     (who should judge this DoD) and candidate gaps (things that may be missing).
  2. `flashpoint_prompt/2` and `flashpoint_schema/0`: the instructions for the
     headless Claude Code run that builds the survey, runs the panel and
     returns every response row.
  3. `tally/2`: severity counts per gap, ranked. No I/O.
  """

  @scale ["Not needed", "Nice to have", "Important", "Critical"]

  def scale, do: @scale

  @plan_system """
  You are Done First. You have a stripped definition of done (DoD) for a game. It names genre, engine, platform,
  payment and scope, but not the concept. Do two things.

  1. Routing: decide which experts can best judge whether this DoD is complete. Describe them as working
     practitioners (role, platform, engine, business model), e.g. "indie developers who ship single-player
     BabylonJS browser games sold direct to players". Give a short label for an on-screen routing line
     (under 60 characters) and a longer research_objective for the panel generator.
  2. Candidate gaps: list 8 to 10 things a builder like this commonly forgets before launch that are NOT already
     covered by the DoD's sections or specific items. Each is one short, plain sentence a practitioner can rate,
     without jargon. Favor risks specific to this platform, engine and business model over generic advice.
  """

  def plan_system, do: @plan_system

  def plan_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["routing_label", "research_objective", "gaps"],
      "properties" => %{
        "routing_label" => %{"type" => "string"},
        "research_objective" => %{"type" => "string"},
        "gaps" => %{"type" => "array", "items" => %{"type" => "string"}}
      }
    }
  end

  @doc "The planning prompt, from `panel_view` in `cache/dod_draft.json`."
  def plan_prompt(%{"sections_covered" => sections, "specific_items" => items}) do
    """
    ## Sections already covered by generic checklist items
    #{Enum.map_join(sections, "\n", &"- #{&1}")}

    ## Specific items for this game (stripped)
    #{Enum.map_join(items, "\n", &"- #{&1}")}
    """
  end

  @doc "The routing line printed on screen."
  def routing_line(label, n), do: "routing to: #{label} (#{n})"

  @doc "Instructions for the headless Flashpoint run."
  def flashpoint_prompt(plan, panel_view, n) do
    rows = Enum.map_join(plan["gaps"], "\n", &"   - #{&1}")

    context =
      "Sections covered: " <>
        Enum.join(panel_view["sections_covered"], "; ") <>
        ". Specific items: " <> Enum.join(panel_view["specific_items"], " ")

    """
    Use ONLY the mcp__flashpoint tools. Do not publish, email or recruit real people. Do not use Bash; if a job is
    still running, call the status or results tool again.

    1. Call mcp__flashpoint__tool_survey to build a survey titled "Done First gap review" with:
       - An intro shown before the questions: "A developer is about to launch the game described below. Judge
         whether their definition of done is missing anything." followed by this context:
         #{context}
       - Q1, a grid question: "How important is it to add each of these to the definition of done before launch?"
         Rows:
    #{rows}
         Columns, in order: #{Enum.join(@scale, ", ")}.
       - Q2, a text question: "What else is missing from this definition of done that would hurt the launch?"
       If it asks to confirm creating the draft, confirm on the same conversation_id.
       If a tool_survey call times out, the survey may still have been created: look it up by title before
       creating another.
    2. Call mcp__flashpoint__panel with action create_and_run, name "done-first-gap-review", num_respondents #{n},
       research_objective "#{plan["research_objective"]}", and the survey_id from step 1.
    3. Poll with action status until status is completed or failed. Persona generation can sit at the same
       progress for several minutes; that is normal. Keep polling for up to 15 minutes before giving up.

    Return survey_id, job_id, the panel id from run_result.result.analytics_scope.panel_id, and the run_id from
    analytics_scope.run_id. Put anything that went wrong in errors.
    """
  end

  def run_schema do
    ids = ["survey_id", "job_id", "panel_id", "run_id"]

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ids ++ ["errors"],
      "properties" =>
        Map.new(ids, &{&1, %{"type" => "string"}})
        |> Map.put("errors", %{"type" => "array", "items" => %{"type" => "string"}})
    }
  end

  @doc "Instructions for fetching every response row of a finished run."
  def fetch_prompt(ids, gaps) do
    rows = Enum.map_join(gaps, "\n", &"   - #{&1}")

    """
    Use ONLY mcp__flashpoint__tool_survey. Do not publish, email or recruit. Read-only.
    Call it with survey_id "#{ids["survey_id"]}" and a brief asking for every individual response row for
    panel_id "#{ids["panel_id"]}" and run_id "#{ids["run_id"]}": each respondent's occupation, the chosen column for
    every row of the grid question, and the text answer to the open question. If the reply is incomplete, ask again
    on the same conversation_id until you have all rows.

    The grid rows are:
    #{rows}

    Return the rows. For grid answers use the exact row text above as `gap` and the exact column label
    (#{Enum.join(@scale, ", ")}) as `rating`. Put the ids you used in survey_id, panel_id and run_id.
    """
  end

  def flashpoint_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["survey_id", "panel_id", "run_id", "respondents", "errors"],
      "properties" => %{
        "survey_id" => %{"type" => "string"},
        "panel_id" => %{"type" => "string"},
        "run_id" => %{"type" => "string"},
        "errors" => %{"type" => "array", "items" => %{"type" => "string"}},
        "respondents" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["respondent_id", "occupation", "grid", "missing"],
            "properties" => %{
              "respondent_id" => %{"type" => "string"},
              "occupation" => %{"type" => "string"},
              "missing" => %{"type" => "string"},
              "grid" => %{
                "type" => "array",
                "items" => %{
                  "type" => "object",
                  "additionalProperties" => false,
                  "required" => ["gap", "rating"],
                  "properties" => %{
                    "gap" => %{"type" => "string"},
                    "rating" => %{"type" => "string"}
                  }
                }
              }
            }
          }
        }
      }
    }
  end

  @doc """
  Severity counts per gap, ranked by Critical + Important, then Critical.
  Ratings not on the scale are ignored. Returns
  `[%{gap, counts: %{label => n}, urgent: n, total: n}]`.
  """
  def tally(gaps, respondents) do
    zero = Map.new(@scale, &{&1, 0})

    counts =
      for r <- respondents,
          %{"gap" => g, "rating" => rating} <- r["grid"],
          rating in @scale,
          reduce: %{} do
        acc ->
          Map.update(
            acc,
            g,
            Map.put(zero, rating, 1),
            &Map.update!(&1, rating, fn n -> n + 1 end)
          )
      end

    gaps
    |> Enum.map(fn gap ->
      c = Map.get(counts, gap, zero)

      %{
        gap: gap,
        counts: c,
        urgent: c["Critical"] + c["Important"],
        total: Enum.sum(Map.values(c))
      }
    end)
    |> Enum.sort_by(&{-&1.urgent, -&1.counts["Critical"]})
  end

  @doc "Renders the tally as a fixed-width table."
  def table(tally) do
    header = "  Crit  Imp  Nice  No   Gap"

    rows =
      Enum.map(tally, fn %{counts: c, gap: g} ->
        nums =
          Enum.map_join(
            ["Critical", "Important", "Nice to have", "Not needed"],
            "",
            &String.pad_leading("#{c[&1]}", 5)
          )

        nums <> "   " <> g
      end)

    Enum.join([header | rows], "\n")
  end
end
