defmodule Palimpedia.Anchor.FileAdapterTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Anchor.FileAdapter

  @json_content Jason.encode!([
                  %{
                    "title" => "Document 1",
                    "content" => "Content one",
                    "source_id" => "local:doc-001"
                  },
                  %{
                    "title" => "Document 2",
                    "content" => "Content two",
                    "source_id" => "local:doc-002"
                  }
                ])

  @jsonl_content """
  {"title": "Line 1", "content": "First line", "source_id": "local:line-001"}
  {"title": "Line 2", "content": "Second line", "source_id": "local:line-002"}
  """

  setup do
    # Create temp files
    json_path =
      Path.join(System.tmp_dir!(), "test_corpus_#{:erlang.unique_integer([:positive])}.json")

    jsonl_path =
      Path.join(System.tmp_dir!(), "test_corpus_#{:erlang.unique_integer([:positive])}.jsonl")

    File.write!(json_path, @json_content)
    File.write!(jsonl_path, @jsonl_content)

    on_exit(fn ->
      File.rm(json_path)
      File.rm(jsonl_path)
    end)

    %{json_path: json_path, jsonl_path: jsonl_path}
  end

  describe "import_file/1 with JSON" do
    test "imports entities from a JSON array", %{json_path: path} do
      {:ok, result} = FileAdapter.import_file(path)

      assert length(result.entities) == 2
      assert hd(result.entities).title == "Document 1"
      assert hd(result.entities).source_id == "local:doc-001"
      assert result.relationships == []
    end
  end

  describe "import_file/1 with JSONL" do
    test "imports entities from a JSONL file", %{jsonl_path: path} do
      {:ok, result} = FileAdapter.import_file(path)

      assert length(result.entities) == 2
      assert hd(result.entities).title == "Line 1"
    end
  end

  describe "error handling" do
    test "returns error for missing file" do
      assert {:error, {:file_read_error, :enoent}} =
               FileAdapter.import_file("/nonexistent/file.json")
    end

    test "returns error when no file_path given" do
      assert {:error, :no_file_path} = FileAdapter.fetch_entities([])
    end
  end
end
