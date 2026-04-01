defmodule Palimpedia.Generation.LlmClientTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Generation.LlmClient

  @success_response Jason.encode!(%{
                      "content" => [%{"type" => "text", "text" => "Generated content here"}],
                      "model" => "claude-haiku-4-5-20251001",
                      "usage" => %{"input_tokens" => 500, "output_tokens" => 200},
                      "stop_reason" => "end_turn"
                    })

  defp mock_http(response_body, status \\ 200) do
    fn _url, _body, _headers ->
      {:ok, %{status: status, body: response_body}}
    end
  end

  describe "generate/2" do
    test "returns completion from successful API call" do
      assert {:ok, completion} =
               LlmClient.generate("test prompt",
                 api_key: "test-key",
                 http_client: mock_http(@success_response)
               )

      assert completion.content == "Generated content here"
      assert completion.input_tokens == 500
      assert completion.output_tokens == 200
      assert completion.model == "claude-haiku-4-5-20251001"
      assert completion.stop_reason == "end_turn"
    end

    test "passes system prompt when provided" do
      captured_body = :persistent_term.put({__MODULE__, :body}, nil)

      mock_fn = fn _url, body, _headers ->
        send(self(), {:request_body, body})
        {:ok, %{status: 200, body: @success_response}}
      end

      LlmClient.generate("user prompt",
        api_key: "test-key",
        system: "You are a knowledge engine.",
        http_client: mock_fn
      )

      assert_received {:request_body, body}
      assert body.system == "You are a knowledge engine."
    end

    test "returns error when API key is missing" do
      # Ensure env var is not set for this test
      original = System.get_env("ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")

      assert {:error, :missing_api_key} =
               LlmClient.generate("test", http_client: mock_http(@success_response))

      if original, do: System.put_env("ANTHROPIC_API_KEY", original)
    end

    test "returns rate_limited error on 429" do
      assert {:error, :rate_limited} =
               LlmClient.generate("test",
                 api_key: "test-key",
                 http_client: mock_http("", 429)
               )
    end

    test "returns api_error on non-200 status" do
      assert {:error, {:api_error, 500, _}} =
               LlmClient.generate("test",
                 api_key: "test-key",
                 http_client: mock_http("internal error", 500)
               )
    end

    test "returns error on network failure" do
      mock_fn = fn _url, _body, _headers -> {:error, :timeout} end

      assert {:error, :timeout} =
               LlmClient.generate("test", api_key: "test-key", http_client: mock_fn)
    end
  end

  describe "estimate_cost/1" do
    test "estimates cost for haiku model" do
      completion = %{
        input_tokens: 1000,
        output_tokens: 500,
        model: "claude-haiku-4-5-20251001"
      }

      cost = LlmClient.estimate_cost(completion)
      assert cost > 0.0
      # Haiku is cheap: ~$0.00025 input + $0.000625 output = ~$0.000875
      assert cost < 0.01
    end
  end
end
