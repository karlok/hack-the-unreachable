defmodule DoneFirst.Dotenv do
  @moduledoc """
  Minimal `.env` loader. Sets variables that are not already set in the environment.
  """

  @doc "Loads `path` into the environment. Returns `:ok` or `{:error, reason}`."
  def load(path \\ ".env") do
    with {:ok, contents} <- File.read(path) do
      contents
      |> parse()
      |> Enum.each(fn {key, value} ->
        if System.get_env(key) == nil, do: System.put_env(key, value)
      end)
    end
  end

  @doc "Parses `.env` text into a list of `{key, value}` pairs."
  def parse(contents) do
    contents
    |> String.split(~r/\R/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.flat_map(&parse_line/1)
  end

  defp parse_line(line) do
    line = String.replace_prefix(line, "export ", "")

    case String.split(line, "=", parts: 2) do
      [key, value] -> [{String.trim(key), unquote_value(String.trim(value))}]
      _ -> []
    end
  end

  defp unquote_value(<<q, rest::binary>> = value) when q in [?", ?'] do
    if String.ends_with?(rest, <<q>>), do: String.slice(rest, 0..-2//1), else: value
  end

  defp unquote_value(value), do: value
end
