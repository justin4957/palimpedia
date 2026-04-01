defmodule Palimpedia.Anchor.HttpClient do
  @moduledoc """
  HTTP client abstraction for anchor corpus adapters.

  Wraps Req for production use, but can be replaced in tests
  via the `:http_client` option on adapter calls.
  """

  @type response :: %{status: integer(), body: term(), headers: [{String.t(), String.t()}]}

  @callback get(url :: String.t(), opts :: keyword()) :: {:ok, response()} | {:error, term()}

  @doc "Makes an HTTP GET request using the configured client."
  def get(url, opts \\ []) do
    case Req.get(url, opts) do
      {:ok, %Req.Response{status: status, body: body, headers: headers}} ->
        {:ok, %{status: status, body: body, headers: headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
