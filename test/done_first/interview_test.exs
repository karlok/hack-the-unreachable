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
        "questions" => ["Which languages?"],
        "targets" => [],
        "done" => false
      }

      assert {:ask, state, ["Which languages?"], [%{label: "Multiplayer", count: 2}]} =
               Interview.apply_decision(state, decision)

      assert [%{key: "settings"}] = Interview.remaining(state)
    end

    test "drops single items by section_key/item_key and hides emptied sections" do
      state = Interview.new(@sections)

      decision = %{
        "drop" => [],
        "drop_items" => [
          %{"item" => "settings/a", "reason" => "no settings"},
          %{"item" => "multiplayer/b", "reason" => "solo"},
          %{"item" => "multiplayer/nope", "reason" => "?"}
        ],
        "questions" => ["q"],
        "targets" => [],
        "done" => false
      }

      assert {:ask, state, ["q"], shown} = Interview.apply_decision(state, decision)
      assert Enum.sum(Enum.map(shown, & &1.count)) == 2
      assert [%{key: "multiplayer", items: [%{key: "c"}]}] = Interview.remaining(state)
    end

    test "does not drop a section twice" do
      state = Interview.new(@sections)
      drop = %{"section_key" => "multiplayer", "reason" => "solo"}
      decision = %{"drop" => [drop], "questions" => ["q"], "targets" => [], "done" => false}

      {:ask, state, _, _} = Interview.apply_decision(state, decision)
      assert {:ask, state, _, []} = Interview.apply_decision(state, decision)
      assert length(state.dropped) == 1
    end

    test "caps the batch at max_turns and stops once it is reached" do
      state = Interview.new(@sections, max_turns: 2) |> Interview.record_answer("q", "a")

      decision = %{
        "drop" => [],
        "questions" => ["one?", "two?"],
        "targets" => [],
        "done" => false
      }

      assert {:ask, state, ["one?"], []} = Interview.apply_decision(state, decision)

      state = Interview.record_answer(state, "one?", "a")
      assert {:done, _, []} = Interview.apply_decision(state, decision)
    end
  end

  test "drop_line/1 counts dropped items" do
    dropped = [
      %{label: "Settings", count: 1},
      %{label: "Multiplayer", count: 2},
      %{label: "Settings", count: 2}
    ]

    assert Interview.drop_line(dropped) == "dropped 5 questions: Settings (3), Multiplayer (2)"

    assert Interview.drop_line([%{label: "Settings", count: 1}]) ==
             "dropped 1 question: Settings (1)"
  end
end
