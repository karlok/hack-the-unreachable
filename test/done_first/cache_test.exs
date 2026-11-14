defmodule DoneFirst.CacheTest do
  use ExUnit.Case, async: true

  alias DoneFirst.Cache

  @moduletag :tmp_dir

  describe "fetch/3" do
    test "runs the function once, then replays from disk", %{tmp_dir: dir} do
      assert {:ok, %{"n" => 1}, :live} = Cache.fetch("Run 1", fn -> {:ok, %{n: 1}} end, dir)
      assert {:ok, %{"n" => 1}, :cached} = Cache.fetch("Run 1", fn -> flunk("called") end, dir)
    end

    test "does not cache errors", %{tmp_dir: dir} do
      assert {:error, :boom} = Cache.fetch("bad", fn -> {:error, :boom} end, dir)
      refute File.exists?(Cache.path("bad", dir))
    end
  end
end
