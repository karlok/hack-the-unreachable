defmodule DoneFirst.InterviewTest do
  use ExUnit.Case, async: true

  alias DoneFirst.{Bank, Interview}

  @sections [
    %{key: "settings", label: "Settings", source: "core", items: [%{key: "a", description: "x"}]},
    %{
      key: "multiplayer",
      label: "Multiplayer",
      source: "core",
      items: [%{key: "b", description: "y"}, %{key: "c", description: "z"}]
    }
  ]

  describe "Bank.normalize/2" do
    test "turns freeform subsections into items" do
      raw = %{
        "key" => "unique_content",
        "label" => "Unique",
        "subsections" => [
          %{"key" => "core_mechanics", "label" => "Mechanics", "description" => "List them."}
        ]
      }

      assert %{items: [%{key: "core_mechanics", description: "Mechanics: List them."}]} =
               Bank.normalize(raw, "core")
    end
  end

  describe "apply_decision/2" do
    test "drops known sections, ignores unknown ones, and asks the next question" do
      state = Interview.new(@sections)

      decision = %{
        "drop" => [
          %{"section_key" => "multiplayer", "reason" => "single-player"},
          %{"section_key" => "made_up", "reason" => "?"}
        ],
        "question" => "Which languages?",
        "targets" => [],
        "done" => false
      }

      assert {:ask, state, "Which languages?", [%{key: "multiplayer"}]} =
               Interview.apply_decision(state, decision)

      assert [%{key: "settings"}] = Interview.remaining(state)
    end

    test "does not drop a section twice" do
      state = Interview.new(@sections)
      drop = %{"section_key" => "multiplayer", "reason" => "solo"}
      decision = %{"drop" => [drop], "question" => "q", "targets" => [], "done" => false}

      {:ask, state, _, _} = Interview.apply_decision(state, decision)
      assert {:ask, state, _, []} = Interview.apply_decision(state, decision)
      assert length(state.dropped) == 1
    end

    test "stops at max_turns even if the model keeps asking" do
      state = Interview.new(@sections, max_turns: 1) |> Interview.record_answer("q", "a")
      decision = %{"drop" => [], "question" => "another?", "targets" => [], "done" => false}
      assert {:done, _, []} = Interview.apply_decision(state, decision)
    end
  end

  test "drop_line/1 counts dropped items" do
    dropped = [Map.put(Enum.at(@sections, 1), :reason, "single-player")]
    assert Interview.drop_line(dropped) == "dropped 2 questions: Multiplayer (single-player)"
  end
end
