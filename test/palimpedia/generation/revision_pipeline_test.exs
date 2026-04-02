defmodule Palimpedia.Generation.RevisionPipelineTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Generation.RevisionPipeline

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "revise_node/3" do
    test "returns failure result when LLM is not configured (expected in tests)" do
      # Without an LLM API key, generation fails — but the pipeline should
      # handle the error gracefully and return a result struct
      result =
        RevisionPipeline.revise_node(2, :contradiction,
          llm_opts: [api_key: nil, http_client: fn _, _, _ -> {:error, :test_no_llm} end]
        )

      assert result.node_id == 2
      assert result.trigger == :contradiction
      assert result.success == false
      assert result.error != nil
    end

    test "returns not_found for missing nodes" do
      result = RevisionPipeline.revise_node(999, :manual)
      assert result.success == false
      assert result.error == :not_found
    end
  end

  describe "revise_from_anchor/2" do
    test "processes downstream nodes without crashing" do
      {:ok, results} =
        RevisionPipeline.revise_from_anchor(1,
          hops: 1,
          llm_opts: [api_key: nil, http_client: fn _, _, _ -> {:error, :test_no_llm} end]
        )

      assert is_list(results)

      for result <- results do
        assert result.trigger == :anchor_update
      end
    end
  end

  describe "process_contradictions/1" do
    test "processes without crashing even with no contradictions" do
      {:ok, results} =
        RevisionPipeline.process_contradictions(
          llm_opts: [api_key: nil, http_client: fn _, _, _ -> {:error, :test_no_llm} end]
        )

      assert is_list(results)
    end
  end
end
