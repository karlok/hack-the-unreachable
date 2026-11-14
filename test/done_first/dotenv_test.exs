defmodule DoneFirst.DotenvTest do
  use ExUnit.Case, async: true

  alias DoneFirst.Dotenv

  describe "parse/1" do
    test "reads plain, quoted and exported pairs and skips comments" do
      text = """
      # comment
      A=1
      export B="two words"
      C='x=y'

      """

      assert Dotenv.parse(text) == [{"A", "1"}, {"B", "two words"}, {"C", "x=y"}]
    end
  end
end
