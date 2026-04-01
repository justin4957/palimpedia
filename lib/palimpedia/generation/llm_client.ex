defmodule Palimpedia.Generation.LlmClient do
  @moduledoc """
  Client for the Anthropic Claude Messages API.

  Handles prompt submission, response parsing, token tracking,
  and cost estimation. HTTP transport is injectable for testing.
  """

  require Logger

  @type message :: %{role: String.t(), content: String.t()}

  @type completion :: %{
          content: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          model: String.t(),
          stop_reason: String.t() | nil
        }

  @anthropic_api_url "https://api.anthropic.com/v1/messages"

  @doc """
  Sends a generation request to the Claude API and returns the completion.

  ## Options
    * `:api_key` - Anthropic API key (default: from env ANTHROPIC_API_KEY)
    * `:model` - Model ID (default: from config)
    * `:max_tokens` - Max tokens to generate (default: from config)
    * `:system` - System prompt string
    * `:http_client` - Injectable HTTP function for testing
  """
  def generate(user_prompt, opts \\ []) do
    config = generation_config()
    api_key = Keyword.get(opts, :api_key, System.get_env("ANTHROPIC_API_KEY"))
    model = Keyword.get(opts, :model, config[:model])
    max_tokens = Keyword.get(opts, :max_tokens, config[:max_tokens])
    system_prompt = Keyword.get(opts, :system, nil)
    http_post = Keyword.get(opts, :http_client, &default_http_post/3)

    if is_nil(api_key) do
      {:error, :missing_api_key}
    else
      body = build_request_body(model, max_tokens, system_prompt, user_prompt)
      headers = build_headers(api_key)

      case http_post.(@anthropic_api_url, body, headers) do
        {:ok, %{status: 200, body: response_body}} ->
          parse_response(response_body)

        {:ok, %{status: 429}} ->
          {:error, :rate_limited}

        {:ok, %{status: status, body: response_body}} ->
          Logger.error("Anthropic API error: status=#{status} body=#{inspect(response_body)}")
          {:error, {:api_error, status, response_body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Estimates cost in USD for a completion based on token counts."
  def estimate_cost(%{input_tokens: input, output_tokens: output, model: model}) do
    {input_rate, output_rate} = token_rates(model)
    input * input_rate + output * output_rate
  end

  # --- Private ---

  defp build_request_body(model, max_tokens, system_prompt, user_prompt) do
    body = %{
      model: model,
      max_tokens: max_tokens,
      messages: [%{role: "user", content: user_prompt}]
    }

    if system_prompt do
      Map.put(body, :system, system_prompt)
    else
      body
    end
  end

  defp build_headers(api_key) do
    [
      {"content-type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]
  end

  defp parse_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parse_response(parsed)
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end

  defp parse_response(%{"content" => [%{"text" => text} | _], "usage" => usage} = response) do
    {:ok,
     %{
       content: text,
       input_tokens: usage["input_tokens"] || 0,
       output_tokens: usage["output_tokens"] || 0,
       model: response["model"] || "unknown",
       stop_reason: response["stop_reason"]
     }}
  end

  defp parse_response(other) do
    {:error, {:unexpected_response, other}}
  end

  defp default_http_post(url, body, headers) do
    case Req.post(url, json: body, headers: headers) do
      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:ok, %{status: status, body: response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Cost per token in USD (approximate, Haiku pricing)
  defp token_rates("claude-haiku-4-5-20251001"), do: {0.00000025, 0.00000125}
  defp token_rates(_), do: {0.000003, 0.000015}

  defp generation_config do
    Application.get_env(:palimpedia, Palimpedia.Generation, [])
  end
end
