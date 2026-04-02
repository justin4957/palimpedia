defmodule PalimpediaWeb.FederationController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Federation.{Sync, InstanceRegistry, Protocol}

  @moduledoc "REST API for federation: peer management, subgraph sharing."

  @doc "GET /api/federation/peers — List registered peer instances."
  def list_peers(conn, _params) do
    peers = InstanceRegistry.list_peers()

    json(conn, %{
      data: Enum.map(peers, &peer_to_json/1),
      meta: %{count: length(peers), local_instance: InstanceRegistry.local_instance_id()}
    })
  end

  @doc "POST /api/federation/peers — Register a new peer instance."
  def register_peer(conn, %{"instance_id" => id, "url" => url, "name" => name} = params) do
    trust = parse_trust(Map.get(params, "trust_level"))

    case InstanceRegistry.register_peer(id, url, name, trust_level: trust) do
      {:ok, peer} ->
        conn |> put_status(201) |> json(%{data: peer_to_json(peer)})
    end
  end

  def register_peer(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Required: instance_id, url, name"})
  end

  @doc "POST /api/federation/export/:node_id — Export a subgraph for sharing."
  def export(conn, %{"node_id" => node_id_str} = params) do
    hops = Map.get(params, "hops", "2") |> String.to_integer()

    case Integer.parse(node_id_str) do
      {node_id, ""} ->
        case Sync.export_subgraph(node_id, hops: hops) do
          {:ok, result} ->
            json(conn, %{
              data: %{
                nodes_exported: result.nodes_exported,
                edges_exported: result.edges_exported,
                protocol: Protocol.version()
              },
              message: result.message
            })

          {:error, reason} ->
            conn |> put_status(422) |> json(%{error: inspect(reason)})
        end

      _ ->
        conn |> put_status(400) |> json(%{error: "Invalid node ID"})
    end
  end

  @doc "POST /api/federation/import — Import a federation message."
  def import_message(conn, %{"message" => message_json}) do
    case Sync.import_message(message_json) do
      {:ok, result} ->
        json(conn, %{
          data: %{
            nodes_imported: result.nodes_imported,
            edges_imported: result.edges_imported,
            skipped: result.skipped,
            errors: length(result.errors)
          }
        })

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  def import_message(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Required: message (JSON string)"})
  end

  defp peer_to_json(peer) do
    %{
      instance_id: peer.instance_id,
      url: peer.url,
      name: peer.name,
      trust_level: peer.trust_level,
      last_sync_at: peer.last_sync_at && DateTime.to_iso8601(peer.last_sync_at),
      registered_at: DateTime.to_iso8601(peer.registered_at)
    }
  end

  defp parse_trust("trusted"), do: :trusted
  defp parse_trust("verified"), do: :verified
  defp parse_trust(_), do: :untrusted
end
