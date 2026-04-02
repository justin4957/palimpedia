defmodule PalimpediaWeb.DomainController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Domain.Config

  @moduledoc "REST API for domain configuration and vertical deployment info."

  @doc "GET /api/domains — List all available domain profiles."
  def index(conn, _params) do
    domains =
      Config.available()
      |> Enum.map(fn id ->
        profile = Config.get(id)

        %{
          id: profile.id,
          name: profile.name,
          description: profile.description,
          edge_types: profile.edge_types,
          corpus_source_count: length(profile.corpus_sources),
          wikidata_qid_count: length(profile.wikidata_root_qids),
          search_query_count: length(profile.search_queries)
        }
      end)

    json(conn, %{
      data: domains,
      meta: %{active: Config.active().id, count: length(domains)}
    })
  end

  @doc "GET /api/domains/:id — Get a specific domain profile."
  def show(conn, %{"id" => id_str}) do
    domain_id = String.to_existing_atom(id_str)

    case Config.get(domain_id) do
      %{} = profile ->
        json(conn, %{
          data: %{
            id: profile.id,
            name: profile.name,
            description: profile.description,
            edge_types: Enum.map(profile.edge_types, &Atom.to_string/1),
            all_edge_types: Enum.map(Config.edge_types_for(domain_id), &Atom.to_string/1),
            wikidata_root_qids: profile.wikidata_root_qids,
            search_queries: profile.search_queries
          }
        })

      {:error, :unknown_domain} ->
        conn |> put_status(404) |> json(%{error: "Unknown domain"})
    end
  rescue
    ArgumentError ->
      conn |> put_status(404) |> json(%{error: "Unknown domain"})
  end

  @doc "GET /api/domains/:id/edge-types — Get edge types for a domain."
  def edge_types(conn, %{"id" => id_str}) do
    domain_id = String.to_existing_atom(id_str)
    types = Config.edge_types_for(domain_id)

    base = Palimpedia.Graph.Edge.valid_types()
    domain_specific = types -- base

    json(conn, %{
      data: %{
        base_types: Enum.map(base, &Atom.to_string/1),
        domain_types: Enum.map(domain_specific, &Atom.to_string/1),
        all_types: Enum.map(types, &Atom.to_string/1)
      }
    })
  rescue
    ArgumentError ->
      conn |> put_status(404) |> json(%{error: "Unknown domain"})
  end
end
