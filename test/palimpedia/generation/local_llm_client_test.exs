defmodule Palimpedia.Generation.LocalLlmClientTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Generation.LocalLlmClient

  @ollama_response Jason.encode!(%{
                     "response" => "Generated text from local LLM",
                     "prompt_eval_count" => 100,
                     "eval_count" => 50
                   })

  @openai_response Jason.encode!(%{
                     "choices" => [%{"message" => %{"content" => "OpenAI-compatible response"}}],
                     "usage" => %{"prompt_tokens" => 200, "completion_tokens" => 80}
                   })

  defp mock_http(response_body) do
    fn _url, _body, _headers ->
      {:ok, %{status: 200, body: response_body}}
    end
  end

  describe "generate/2 with Ollama" do
    test "returns completion from Ollama" do
      {:ok, completion} =
        LocalLlmClient.generate("test prompt",
          provider: :ollama,
          base_url: "http://localhost:11434",
          model: "llama3",
          http_client: mock_http(@ollama_response)
        )

      assert completion.content == "Generated text from local LLM"
      assert completion.input_tokens == 100
      assert completion.output_tokens == 50
      assert completion.model == "llama3"
    end
  end

  describe "generate/2 with OpenAI-compatible" do
    test "returns completion from OpenAI-compatible server" do
      {:ok, completion} =
        LocalLlmClient.generate("test prompt",
          provider: :openai_compatible,
          base_url: "http://localhost:8080",
          model: "local-model",
          http_client: mock_http(@openai_response)
        )

      assert completion.content == "OpenAI-compatible response"
      assert completion.input_tokens == 200
      assert completion.output_tokens == 80
    end
  end

  describe "error handling" do
    test "returns error on HTTP failure" do
      mock_fn = fn _url, _body, _headers -> {:error, :econnrefused} end

      assert {:error, :econnrefused} =
               LocalLlmClient.generate("test", provider: :ollama, http_client: mock_fn)
    end

    test "returns error for unknown provider" do
      assert {:error, {:unknown_provider, :nonexistent}} =
               LocalLlmClient.generate("test",
                 provider: :nonexistent,
                 http_client: fn _, _, _ -> {:ok, %{status: 200, body: "{}"}} end
               )
    end
  end
end
