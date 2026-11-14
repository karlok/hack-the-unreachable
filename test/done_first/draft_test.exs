defmodule DoneFirst.DraftTest do
  use ExUnit.Case, async: true

  alias DoneFirst.Draft

  @draft %{
    "game_title" => "Ember Depths",
    "protected_terms" => ["Ember Depths", "caverns"],
    "tailored" => [
      %{
        "section_key" => "web_launch",
        "draft" => "Ember Depths caverns generate in under 2 s in Chrome",
        "stripped" => "Procedural levels generate in under 2 s in Chrome",
        "removed" => ["Ember Depths", "caverns"]
      },
      %{
        "section_key" => "web_direct_sales",
        "draft" => "$8 Stripe checkout unlocks the game",
        "stripped" => "$8 Stripe checkout unlocks the game",
        "removed" => []
      }
    ]
  }

  describe "leaks/1" do
    test "finds nothing when stripped text is clean" do
      assert Draft.leaks(@draft) == []
    end

    test "flags a removed term that is still in the stripped text, case-insensitively" do
      [first | rest] = @draft["tailored"]
      leaky = %{@draft | "tailored" => [%{first | "stripped" => "The CAVERNS load fast"} | rest]}
      assert [%{term: "caverns"}] = Draft.leaks(leaky)
    end

    test "matches whole words only" do
      [first | rest] = @draft["tailored"]
      ok = %{@draft | "tailored" => [%{first | "stripped" => "Supercaverns2 are fine"} | rest]}
      assert Draft.leaks(ok) == []
    end
  end

  test "leaks/1 ignores technical phrases like depth sorting" do
    draft = %{
      "game_title" => "X",
      "protected_terms" => [],
      "tailored" => [
        %{
          "section_key" => "a",
          "draft" => "final depth",
          "stripped" => "correct depth sorting",
          "removed" => ["depth"]
        },
        %{
          "section_key" => "b",
          "draft" => "final depth",
          "stripped" => "the final depth",
          "removed" => ["depth"]
        }
      ]
    }

    assert [%{stripped: "the final depth"}] = Draft.leaks(draft)
  end

  test "panel_view/2 carries stripped items and section headings only" do
    kept = [%{"label" => "Settings Menu", "items" => [%{}, %{}]}]
    view = Draft.panel_view(@draft, kept)
    assert view["sections_covered"] == ["Settings Menu (2 items)"]
    refute Enum.any?(view["specific_items"], &String.contains?(&1, "Ember Depths"))
  end

  test "changed/1 keeps only rows the stripping altered" do
    assert [{"Ember Depths caverns" <> _, "Procedural levels" <> _}] = Draft.changed(@draft)
  end

  test "wrap/2 keeps lines within width" do
    lines = Draft.wrap("one two three four five six seven", 10)
    assert Enum.all?(lines, &(String.length(&1) <= 10))
    assert Enum.join(lines, " ") == "one two three four five six seven"
  end
end
