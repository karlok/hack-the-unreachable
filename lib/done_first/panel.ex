defmodule DoneFirst.Panel do
  @moduledoc """
  The one door to Flashpoint. Cache-first: a hit replays from `cache/`; a miss
  shells out to headless Claude Code (`claude -p`), which talks to the
  Flashpoint MCP server under Karlo's OAuth login. Elixir never signs payments.

  Run from the repo root: the Flashpoint MCP server is registered for that folder.
  """

  alias DoneFirst.Cache

  @flashpoint_tools "mcp__flashpoint"

  @doc """
  Runs `prompt` through Claude Code with Flashpoint tools allowed, caching the
  result under `key`.

  Returns `{:ok, envelope, :cached | :live}` where `envelope` is Claude Code's
  JSON output (`"result"`, `"total_cost_usd"`, `"duration_ms"`, ...).

  Options: `:schema` (a JSON schema; the parsed answer lands in
  `envelope["structured_output"]`), `:cmd` (the binary, for tests).
  """
  def call(key, prompt, opts \\ []) do
    Cache.fetch("panel_" <> key, fn -> run_claude(prompt, opts) end)
  end

  @doc "Bypasses the cache and overwrites the entry. Use for a fresh live run."
  def call_live(key, prompt, opts \\ []) do
    with {:ok, envelope} <- run_claude(prompt, opts),
         :ok <- Cache.put("panel_" <> key, envelope) do
      {:ok, envelope, :live}
    end
  end

  defp run_claude(prompt, opts) do
    schema_args =
      case Keyword.get(opts, :schema) do
        nil -> []
        schema -> ["--json-schema", Jason.encode!(schema)]
      end

    args =
      ["-p", prompt, "--output-format", "json", "--allowedTools", @flashpoint_tools] ++
        schema_args

    cmd = Keyword.get(opts, :cmd, "claude")

    # stdin from /dev/null so `claude -p` does not wait on an open pipe.
    {out, code} =
      System.cmd("sh", ["-c", ~s(exec "$0" "$@" < /dev/null), cmd | args],
        stderr_to_stdout: false,
        # Keep Flashpoint and Claude Code on the subscription login, not the API key.
        env: [{"ANTHROPIC_API_KEY", nil}]
      )

    with 0 <- code,
         {:ok, %{"is_error" => false} = envelope} <- Jason.decode(out) do
      {:ok, envelope}
    else
      {:ok, envelope} -> {:error, {:claude_error, envelope}}
      {:error, _} -> {:error, {:bad_output, out}}
      exit_code -> {:error, {:exit, exit_code, out}}
    end
  end
end
