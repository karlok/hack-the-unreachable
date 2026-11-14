defmodule DoneFirst.Bank do
  @moduledoc """
  The question bank: core DoD sections plus one genre entry plus one platform
  template, flattened into a single list of sections.

  Each section is `%{key, label, source, items: [%{key, description}]}`.
  Freeform subsections (the core `unique_content` section) become items whose
  description is the subsection prompt.
  """

  @core "../dod-examples/dod_template.json"
  @genres "../dod-examples/dod_genre_templates.json"
  @platform "priv/templates/web_direct.json"

  @doc """
  Loads the bank from disk. Options: `:core`, `:genres`, `:platform` (paths),
  `:genre` (genre key, default `"roguelite"`).
  """
  def load(opts \\ []) do
    genre_key = Keyword.get(opts, :genre, "roguelite")

    with {:ok, core} <- read_json(Keyword.get(opts, :core, @core)),
         {:ok, genres} <- read_json(Keyword.get(opts, :genres, @genres)),
         {:ok, platform} <- read_json(Keyword.get(opts, :platform, @platform)),
         {:ok, genre} <- find_genre(genres, genre_key) do
      {:ok, build(core, genre, platform)}
    end
  end

  @doc "Builds the flat section list from decoded JSON. Pure."
  def build(core, genre, platform) do
    Enum.map(core["sections"], &normalize(&1, "core")) ++
      Enum.map(genre["additional_sections"], &normalize(&1, "genre:" <> genre["key"])) ++
      Enum.map(platform["additional_sections"], &normalize(&1, "platform:" <> platform["key"]))
  end

  @doc "Normalizes one raw section into the bank's section shape."
  def normalize(%{"subsections" => subs} = raw, source) do
    items =
      Enum.map(subs, &%{key: &1["key"], description: &1["label"] <> ": " <> &1["description"]})

    %{key: raw["key"], label: raw["label"], source: source, items: items}
  end

  def normalize(raw, source) do
    items = Enum.map(raw["items"], &%{key: &1["key"], description: &1["description"]})
    %{key: raw["key"], label: raw["label"], source: source, items: items}
  end

  @doc "Total number of items across `sections`."
  def item_count(sections), do: Enum.reduce(sections, 0, &(length(&1.items) + &2))

  defp find_genre(%{"genres" => genres}, key) do
    case Enum.find(genres, &(&1["key"] == key)) do
      nil -> {:error, {:unknown_genre, key}}
      genre -> {:ok, genre}
    end
  end

  defp read_json(path) do
    with {:ok, text} <- File.read(path) do
      Jason.decode(text)
    end
  end
end
