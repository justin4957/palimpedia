defmodule Palimpedia.Anchor.FileAdapter do
  @moduledoc """
  Adapter for importing proprietary anchor corpus from local files.

  Supports JSON and JSONL formats for air-gapped deployments where
  external APIs are not available. Each record becomes an anchor node.

  ## File Format (JSON)

      [
        {"title": "Internal Policy 1", "content": "...", "source_id": "internal:pol-001"},
        {"title": "Classified Report", "content": "...", "source_id": "classified:rpt-042"}
      ]

  ## File Format (JSONL)

      {"title": "Document 1", "content": "...", "source_id": "local:doc-001"}
      {"title": "Document 2", "content": "...", "source_id": "local:doc-002"}
  """

  @behaviour Palimpedia.Anchor.Adapter

  @impl true
  def fetch_entity(identifier, opts \\ []) do
    fetch_entities([identifier], opts)
  end

  @impl true
  def fetch_entities(_identifiers, opts \\ []) do
    file_path = Keyword.get(opts, :file_path)

    if file_path do
      import_file(file_path)
    else
      {:error, :no_file_path}
    end
  end

  @impl true
  def search(_query, _opts \\ []) do
    {:error, :search_not_supported}
  end

  @doc "Imports anchor entities from a JSON or JSONL file."
  def import_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        ext = Path.extname(file_path)
        parse_file(content, ext)

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  defp parse_file(content, ext) when ext in [".jsonl", ".ndjson"] do
    entities =
      content
      |> String.split("\n")
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&parse_record/1)
      |> Enum.reject(&is_nil/1)

    {:ok, %{entities: entities, relationships: []}}
  end

  defp parse_file(content, _ext) do
    case Jason.decode(content) do
      {:ok, records} when is_list(records) ->
        entities = Enum.map(records, &record_to_entity/1) |> Enum.reject(&is_nil/1)
        {:ok, %{entities: entities, relationships: []}}

      {:ok, record} when is_map(record) ->
        case record_to_entity(record) do
          nil -> {:ok, %{entities: [], relationships: []}}
          entity -> {:ok, %{entities: [entity], relationships: []}}
        end

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp parse_record(line) do
    case Jason.decode(line) do
      {:ok, record} -> record_to_entity(record)
      _ -> nil
    end
  end

  defp record_to_entity(%{"title" => title, "content" => content} = record) do
    source_id =
      record["source_id"] ||
        "local:#{:crypto.hash(:md5, title) |> Base.encode16(case: :lower) |> String.slice(0, 8)}"

    %{
      title: title,
      content: content,
      source_id: source_id,
      properties: Map.drop(record, ["title", "content", "source_id"])
    }
  end

  defp record_to_entity(_), do: nil
end
