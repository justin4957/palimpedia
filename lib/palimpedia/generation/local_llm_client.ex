defmodule Palimpedia.Generation.LocalLlmClient do
  @moduledoc """
  Local LLM client for air-gapped deployments.

  Supports Ollama and any OpenAI-compatible local inference server.
  No external API calls — all generation runs on the local network.

  ## Configuration

      config :palimpedia, Palimpedia.Generation.LocalLlmClient,
        base_url: "http://localhost:11434",
        model: "llama3",
        provider: :ollama
  """

  require Logger

  @doc """
  Generates a completion using the local LLM.

  Compatible with the same interface as LlmClient.generate/2.
  """
  def generate(user_prompt, opts \\ []) do
    config = Application.get_env(:palimpedia, __MODULE__, [])
    provider = Keyword.get(config, :provider, Keyword.get(opts, :provider, :ollama))

    base_url =
      Keyword.get(config, :base_url, Keyword.get(opts, :base_url, "http://localhost:11434"))

    model = Keyword.get(config, :model, Keyword.get(opts, :model, "llama3"))
    system_prompt = Keyword.get(opts, :system)
    http_post = Keyword.get(opts, :http_client, &default_http_post/3)

    case provider do
      :ollama ->
        generate_ollama(base_url, model, system_prompt, user_prompt, http_post)

      :openai_compatible ->
        generate_openai_compatible(base_url, model, system_prompt, user_prompt, http_post)

      _ ->
        {:error, {:unknown_provider, provider}}
    end
  end

  defp generate_ollama(base_url, model, system_prompt, user_prompt, http_post) do
    url = "#{base_url}/api/generate"

    body = %{
      model: model,
      prompt: user_prompt,
      stream: false
    }

    body = if system_prompt, do: Map.put(body, :system, system_prompt), else: body

    case http_post.(url, body, [{"content-type", "application/json"}]) do
      {:ok, %{status: 200, body: response_body}} ->
        parse_ollama_response(response_body, model)

      {:ok, %{status: status}} ->
        {:error, {:local_llm_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_openai_compatible(base_url, model, system_prompt, user_prompt, http_post) do
    url = "#{base_url}/v1/chat/completions"

    messages = []

    messages =
      if system_prompt, do: [%{role: "system", content: system_prompt} | messages], else: messages

    messages = messages ++ [%{role: "user", content: user_prompt}]

    body = %{model: model, messages: messages}

    case http_post.(url, body, [{"content-type", "application/json"}]) do
      {:ok, %{status: 200, body: response_body}} ->
        parse_openai_response(response_body, model)

      {:ok, %{status: status}} ->
        {:error, {:local_llm_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_ollama_response(body, model) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parse_ollama_response(parsed, model)
      {:error, _} -> {:error, :invalid_response}
    end
  end

  defp parse_ollama_response(%{"response" => text} = resp, model) do
    {:ok,
     %{
       content: text,
       input_tokens: resp["prompt_eval_count"] || 0,
       output_tokens: resp["eval_count"] || 0,
       model: model,
       stop_reason: "stop"
     }}
  end

  defp parse_ollama_response(_, _), do: {:error, :unexpected_response}

  defp parse_openai_response(body, model) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parse_openai_response(parsed, model)
      {:error, _} -> {:error, :invalid_response}
    end
  end

  defp parse_openai_response(
         %{"choices" => [%{"message" => %{"content" => text}} | _]} = resp,
         model
       ) do
    usage = resp["usage"] || %{}

    {:ok,
     %{
       content: text,
       input_tokens: usage["prompt_tokens"] || 0,
       output_tokens: usage["completion_tokens"] || 0,
       model: model,
       stop_reason: "stop"
     }}
  end

  defp parse_openai_response(_, _), do: {:error, :unexpected_response}

  defp default_http_post(url, body, headers) do
    case Req.post(url, json: body, headers: headers) do
      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:ok, %{status: status, body: response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
