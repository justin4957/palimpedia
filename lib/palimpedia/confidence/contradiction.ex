defmodule Palimpedia.Confidence.Contradiction do
  @moduledoc """
  Contradiction detection and resolution.

  When two documents make conflicting claims, the system flags the
  contradiction and triggers a subgraph review. Users can also
  flag contradictions directly (Tier 3 interaction).
  """

  @type contradiction :: %{
          id: String.t() | nil,
          node_a_id: String.t(),
          node_b_id: String.t(),
          description: String.t(),
          status: contradiction_status(),
          flagged_by: :system | :user,
          flagged_at: DateTime.t()
        }

  @type contradiction_status :: :open | :reviewing | :resolved | :dismissed

  @doc """
  Flags a contradiction between two nodes.
  Triggers confidence review for the affected subgraph.
  """
  @callback flag(String.t(), String.t(), String.t(), keyword()) ::
              {:ok, contradiction()} | {:error, term()}

  @doc """
  Returns all open contradictions, optionally filtered by node ID.
  """
  @callback list_open(keyword()) :: {:ok, [contradiction()]} | {:error, term()}

  @doc """
  Resolves a contradiction, updating confidence scores for affected nodes.
  """
  @callback resolve(String.t(), :confirmed | :dismissed, keyword()) ::
              {:ok, contradiction()} | {:error, term()}
end
