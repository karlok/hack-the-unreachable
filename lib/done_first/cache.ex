defmodule DoneFirst.Cache do
  @moduledoc """
  Disk cache for slow or paid calls. Every entry is a pretty-printed JSON file
  under `cache/`, so a demo can replay any run without calling out.
  """

  @dir "cache"

  @doc """
  Returns the cached value for `key`, or runs `fun` and caches its `{:ok, value}`.

  Returns `{:ok, value, :cached}`, `{:ok, value, :live}`, or the error from `fun`.
  """
  def fetch(key, fun, dir \\ @dir) when is_function(fun, 0) do
    path = path(key, dir)

    case read(path) do
      {:ok, value} ->
        {:ok, value, :cached}

      :miss ->
        # Round-trip through JSON so a live value looks exactly like a replay.
        with {:ok, value} <- fun.(),
             :ok <- write(path, value) do
          {:ok, value |> Jason.encode!() |> Jason.decode!(), :live}
        end
    end
  end

  @doc "Writes `value` under `key`, replacing any earlier entry."
  def put(key, value, dir \\ @dir), do: write(path(key, dir), value)

  @doc "File path for `key`. Keys are slugged so any string is safe."
  def path(key, dir \\ @dir) do
    slug = key |> String.downcase() |> String.replace(~r/[^a-z0-9_.-]+/, "_")
    Path.join(dir, slug <> ".json")
  end

  defp read(path) do
    with {:ok, body} <- File.read(path),
         {:ok, value} <- Jason.decode(body) do
      {:ok, value}
    else
      _ -> :miss
    end
  end

  defp write(path, value) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, Jason.encode_to_iodata!(value, pretty: true))
    end
  end
end
