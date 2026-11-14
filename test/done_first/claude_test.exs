defmodule DoneFirst.ClaudeTest do
  use ExUnit.Case, async: true

  alias DoneFirst.Claude

  describe "fallback?/1" do
    test "falls back on a spend-limit 429, a missing key, or an auth failure" do
      spend = %{"error" => %{"details" => %{"error_code" => "enforced_spend_limit_reached"}}}
      assert Claude.fallback?({:http, 429, spend})
      assert Claude.fallback?(:missing_anthropic_api_key)
      assert Claude.fallback?({:http, 401, %{}})
    end

    test "does not fall back on an ordinary rate limit or a refusal" do
      refute Claude.fallback?({:http, 429, %{"error" => %{"type" => "rate_limit_error"}}})
      refute Claude.fallback?({:refusal, nil})
    end
  end
end
