defmodule DoneFirst.ReviewTest do
  use ExUnit.Case, async: true

  alias DoneFirst.Review

  test "tally/2 counts ratings per gap, ignores off-scale ratings, and ranks by urgency" do
    gaps = ["A", "B"]

    respondents = [
      %{
        "grid" => [
          %{"gap" => "A", "rating" => "Nice to have"},
          %{"gap" => "B", "rating" => "Critical"}
        ]
      },
      %{
        "grid" => [
          %{"gap" => "A", "rating" => "Important"},
          %{"gap" => "B", "rating" => "Important"}
        ]
      },
      %{"grid" => [%{"gap" => "A", "rating" => "Maybe?"}]}
    ]

    assert [%{gap: "B", urgent: 2, total: 2}, %{gap: "A", urgent: 1, total: 2}] =
             Review.tally(gaps, respondents)
  end

  test "tally/2 keeps gaps nobody rated, with zero counts" do
    assert [%{gap: "A", total: 0}] = Review.tally(["A"], [])
  end
end
