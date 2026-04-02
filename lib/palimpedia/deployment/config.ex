defmodule Palimpedia.Deployment.Config do
  @moduledoc """
  Deployment configuration for institutional and air-gapped instances.

  Supports three deployment modes:
  - `:standard` — Full internet access, Anthropic API, public federation
  - `:restricted` — Internet access but proprietary corpus isolation
  - `:air_gapped` — No internet, local LLM, no outbound federation

  ## Configuration

      config :palimpedia, Palimpedia.Deployment.Config,
        mode: :standard,
        llm_provider: :anthropic,
        federation_enabled: true,
        proprietary_labels: ["proprietary", "classified", "internal"]
  """

  @type deployment_mode :: :standard | :restricted | :air_gapped

  @doc "Returns the current deployment mode."
  def mode do
    config() |> Keyword.get(:mode, :standard)
  end

  @doc "Returns the configured LLM provider."
  def llm_provider do
    config() |> Keyword.get(:llm_provider, :anthropic)
  end

  @doc "Returns whether federation is enabled."
  def federation_enabled? do
    case mode() do
      :air_gapped -> false
      _ -> config() |> Keyword.get(:federation_enabled, true)
    end
  end

  @doc "Returns whether external API calls are allowed."
  def external_apis_allowed? do
    mode() != :air_gapped
  end

  @doc "Returns the list of proprietary labels that should not be federated."
  def proprietary_labels do
    config() |> Keyword.get(:proprietary_labels, [])
  end

  @doc "Checks if a node is proprietary (should not be shared via federation)."
  def proprietary?(node) do
    labels = proprietary_labels()

    if labels == [] do
      false
    else
      provenance = node.provenance || []

      Enum.any?(provenance, fn prov ->
        Enum.any?(labels, fn label ->
          String.contains?(String.downcase(prov), String.downcase(label))
        end)
      end)
    end
  end

  @doc "Returns the full deployment configuration summary."
  def summary do
    %{
      mode: mode(),
      llm_provider: llm_provider(),
      federation_enabled: federation_enabled?(),
      external_apis_allowed: external_apis_allowed?(),
      proprietary_labels: proprietary_labels()
    }
  end

  defp config do
    Application.get_env(:palimpedia, __MODULE__, [])
  end
end
