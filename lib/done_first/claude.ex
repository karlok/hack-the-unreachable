defmodule DoneFirst.Claude do
  @moduledoc """
  Thin client for the Anthropic Messages API (raw HTTP via Req; there is no
  official Elixir SDK).

  Uses `claude-opus-5-5` with server-side refusal fallbacks enabled
  (`fallbacks: "default"`), so a safety decline is retried on a fallback model
  inside the same call.
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
    with {:ok, body} <- request(system, prompt, %{}, opts) do
      {:ok, %{text: text_of(body), usage: body["usage"]}}
    end
  end

  @doc """
  Completion constrained to a JSON schema. Returns `{:ok, %{data: map, usage: usage}}`.

  Every object in `schema` needs `"additionalProperties" => false` and `"required"`.
  """
  def json(system, prompt, schema, opts \\ []) do
    format = %{format: %{type: "json_schema", schema: schema}}

    with {:ok, body} <- request(system, prompt, format, opts),
         {:ok, data} <- Jason.decode(text_of(body)) do
      {:ok, %{data: data, usage: body["usage"]}}
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
        retry: :transient
      )
      |> handle_response()
    end
  end

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
