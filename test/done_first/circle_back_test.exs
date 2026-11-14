defmodule DoneFirst.CircleBackTest do
  use ExUnit.Case, async: true

  alias DoneFirst.CircleBack

  test "normalize/2 drops out-of-range and duplicate respondents, then sorts by count" do
    catches = [
      %{
        "title" => "A",
        "respondents" => [1, 1, 99],
        "covered_by" => "",
        "baseline_raised" => false,
        "question" => "?"
      },
      %{
        "title" => "B",
        "respondents" => [2, 3, 4],
        "covered_by" => "item",
        "baseline_raised" => true,
        "question" => "?"
      },
      %{
        "title" => "C",
        "respondents" => [0],
        "covered_by" => "",
        "baseline_raised" => false,
        "question" => "?"
      }
    ]

    assert [
             %{"title" => "B", "count" => 3, "covered" => true},
             %{"title" => "A", "count" => 1, "covered" => false}
           ] =
             CircleBack.normalize(catches, 12)
  end

  test "classify/2 separates new, candidate echoes, and draft matches by exact text" do
    catches = [
      %{"covered" => false, "covered_by" => ""},
      %{"covered" => true, "covered_by" => "Rated row"},
      %{"covered" => true, "covered_by" => "Draft item"}
    ]

    assert ["new", "candidate", "draft"] =
             catches |> CircleBack.classify(["Rated row"]) |> Enum.map(& &1["kind"])
  end

  test "trail_line/2 states the count, status and baseline comparison" do
    c = %{"title" => "Rollback plan", "count" => 4, "covered" => false, "baseline_raised" => true}

    assert CircleBack.trail_line(c, 12) ==
             "[4/12] Rollback plan (NEW, single model also raised it)"
  end
end
