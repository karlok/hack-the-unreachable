defmodule DoneFirst.Claude do
  @moduledoc """
  Thin client for the Anthropic Messages API (raw HTTP via Req; there is no
  official Elixir SDK).

  Uses `claude-opus-5-5` with server-side refusal fallbacks enabled
  (`fallbacks: "default"`), so a safety decline is retried on a fallback model
  inside the same call.

  Backends: the API (key from `ANTHROPIC_API_KEY`) or headless Claude Code
  (`claude -p`, billed to the Claude Code login). Set `DONE_FIRST_BACKEND=cli`
  to force the CLI. On a missing key or a spend-limit 429 the client switches
  to the CLI and stays there for the rest of the VM's life.
  """

  @url "https://api.anthropic.com/v1/messages"
  @model "claude-opus-5-5"
  @version "2026-10-21"
  @fallback_beta "server-side-fallback-2026-07-01"

  @doc """
  Plain text completion. Returns `{:ok, %{text: text, usage: usage}}`.

  Options: `:effort` ("low" | "medium" | "high", default "medium"), `:max_tokens`.
  """
  def text(system, prompt, opts \\ []) do
    with_fallback(
      fn ->
        with {:ok, body} <- request(system, prompt, %{}, opts) do
          {:ok, %{text: text_of(body), usage: body["usage"]}}
        end
      end,
      fn ->
        with {:ok, env} <- cli(system, prompt, nil, opts) do
          {:ok, %{text: env["result"], usage: env["usage"]}}
        end
      end
    )
  end

  @doc """
  Completion constrained to a JSON schema. Returns `{:ok, %{data: map, usage: usage}}`.

  Every object in `schema` needs `"additionalProperties" => false` and `"required"`.
  """
  def json(system, prompt, schema, opts \\ []) do
    format = %{format: %{type: "json_schema", schema: schema}}

    with_fallback(
      fn ->
        with {:ok, body} <- request(system, prompt, format, opts),
             {:ok, data} <- Jason.decode(text_of(body)) do
          {:ok, %{data: data, usage: body["usage"]}}
        end
      end,
      fn ->
        case cli(system, prompt, schema, opts) do
          {:ok, %{"structured_output" => data} = env} when is_map(data) ->
            {:ok, %{data: data, usage: env["usage"]}}

          {:ok, env} ->
            {:error, {:cli_no_structured_output, env["result"]}}

          error ->
            error
        end
      end
    )
  end

  @doc "The backend the next call will use: `:api` or `:cli`."
  def backend do
    cond do
      System.get_env("DONE_FIRST_BACKEND") == "cli" -> :cli
      :persistent_term.get({__MODULE__, :backend}, :api) == :cli -> :cli
      true -> :api
    end
  end

  defp with_fallback(api_fun, cli_fun) do
    if backend() == :cli do
      cli_fun.()
    else
      case api_fun.() do
        {:error, reason} = error ->
          if fallback?(reason) do
            IO.puts(
              :stderr,
              "[DoneFirst.Claude] API unavailable (#{inspect(short(reason))}), switching to claude -p"
            )

            :persistent_term.put({__MODULE__, :backend}, :cli)
            cli_fun.()
          else
            error
          end

        ok ->
          ok
      end
    end
  end

  @doc false
  def fallback?(:missing_anthropic_api_key), do: true

  def fallback?(
        {:http, 429,
         %{"error" => %{"details" => %{"error_code" => "enforced_spend_limit_reached"}}}}
      ),
      do: true

  def fallback?({:http, status, _}) when status in [401, 403], do: true
  def fallback?(_), do: false

  defp short({:http, status, _}), do: {:http, status}
  defp short(reason), do: reason

  # Headless Claude Code with no tools and no MCP servers. ANTHROPIC_API_KEY is
  # removed from the child env so it bills the Claude Code login, not the key.
  defp cli(system, prompt, schema, opts) do
    args =
      ["-p", prompt, "--output-format", "json", "--system-prompt", system] ++
        ["--tools", "", "--strict-mcp-config", "--no-session-persistence"] ++
        ["--model", @model, "--effort", Keyword.get(opts, :effort, "medium")] ++
        if(schema, do: ["--json-schema", Jason.encode!(schema)], else: [])

    {out, code} =
      System.cmd("sh", ["-c", ~s(exec "$0" "$@" < /dev/null), "claude" | args],
        env: [{"ANTHROPIC_API_KEY", nil}]
      )

    with 0 <- code,
         {:ok, %{"is_error" => false} = env} <- Jason.decode(out) do
      {:ok, env}
    else
      {:ok, env} -> {:error, {:cli_error, env["result"]}}
      {:error, _} -> {:error, {:cli_bad_output, out}}
      exit_code -> {:error, {:cli_exit, exit_code, out}}
    end
  end

  defp request(system, prompt, output_config, opts) do
    with {:ok, key} <- api_key() do
      body = %{
        model: @model,
        max_tokens: Keyword.get(opts, :max_tokens, 16_000),
        system: system,
        messages: [%{role: "user", content: prompt}],
        output_config: Map.put(output_config, :effort, Keyword.get(opts, :effort, "medium")),
        fallbacks: "default"
      }

      @url
      |> Req.post(
        json: body,
        headers: [
          {"x-api-key", key},
          {"anthropic-version", @version},
          {"anthropic-beta", @fallback_beta}
        ],
        receive_timeout: 300_000,
        retry: &retry?/2
      )
      |> handle_response()
    end
  end

  # Retry transient failures, but never a spend-limit 429 (it will not clear).
  # The retry step runs before the body is decoded, so match on the raw text.
  defp retry?(_req, %Req.Response{status: 429, body: body}) when is_binary(body),
    do: not String.contains?(body, "enforced_spend_limit_reached")

  defp retry?(_req, %Req.Response{status: 429, body: body}),
    do: not fallback?({:http, 429, body})

  defp retry?(_req, %Req.Response{status: status}), do: status in [408, 500, 502, 503, 504, 529]
  defp retry?(_req, _exception), do: true

  defp handle_response(
         {:ok, %Req.Response{status: 200, body: %{"stop_reason" => "refusal"} = body}}
       ),
       do: {:error, {:refusal, body["stop_details"]}}

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}), do: {:ok, body}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http, status, body}}

  defp handle_response({:error, exception}),
    do: {:error, {:transport, Exception.message(exception)}}

  defp text_of(%{"content" => content}) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join(& &1["text"])
  end

  defp api_key do
    case System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_anthropic_api_key}
    end
  end
end
