defmodule Palimpedia.Interaction.Handler do
  @moduledoc """
  Processes user interactions with their full side effects.

  Each tier triggers specific downstream actions:
  - Tier 1: boosts generation queue priority, triggers on-demand evaluation
  - Tier 2: creates edge in graph, enqueues document generation exploring the relationship
  - Tier 3: creates contradiction in store, triggers subgraph confidence review
  """

  alias Palimpedia.Interaction.UserTrust
  alias Palimpedia.GapDetection.GenerationQueue
  alias Palimpedia.Generation.OnDemand
  alias Palimpedia.Confidence.{Contradiction, Updater}
  alias Palimpedia.Graph.Edge

  require Logger

  @doc """
  Handles a Tier 1 node request.

  Side effects:
  - Records interaction for user trust
  - Boosts priority if title already in generation queue
  - Triggers on-demand evaluation if not yet queued
  """
  def handle_node_request(title, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    record_trust(user_id, :node_request)

    # Try to boost existing queue entry
    boosted = boost_queue(title, user_id)

    # If not already queued, trigger on-demand evaluation
    if boosted == 0 do
      evaluate_on_demand(title)
    end

    {:ok, %{title: title, boosted: boosted > 0}}
  end

  @doc """
  Handles a Tier 2 edge assertion.

  Side effects:
  - Records interaction for user trust
  - Creates edge in graph (if both nodes exist)
  - Enqueues document generation exploring the claimed relationship
  """
  def handle_edge_assertion(source_id, target_id, edge_type, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    confidence = Keyword.get(opts, :confidence, 0.5)
    description = Keyword.get(opts, :description)

    record_trust(user_id, :edge_assertion)

    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    # Create edge
    edge = %Edge{
      source_id: source_id,
      target_id: target_id,
      edge_type: edge_type,
      confidence: confidence,
      provenance: if(user_id, do: ["user:#{user_id}"], else: [])
    }

    edge_result = graph_repo.insert_edge(edge)

    # Enqueue generation exploring the relationship
    enqueue_relationship_exploration(source_id, target_id, edge_type, description)

    edge_result
  end

  @doc """
  Handles a Tier 3 contradiction flag.

  Side effects:
  - Records interaction for user trust
  - Creates contradiction in store
  - Triggers confidence review for affected subgraph
  """
  def handle_contradiction_flag(node_a_id, node_b_id, description, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    severity = Keyword.get(opts, :severity, :medium)
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    record_trust(user_id, :contradiction_flag)

    # Create contradiction
    result =
      Contradiction.flag(node_a_id, node_b_id, description,
        severity: severity,
        flagged_by: :user
      )

    # Trigger confidence review for both nodes' neighborhoods
    trigger_confidence_review(node_a_id, graph_repo)
    trigger_confidence_review(node_b_id, graph_repo)

    result
  end

  # --- Private ---

  defp record_trust(nil, _tier), do: :ok

  defp record_trust(user_id, tier) do
    if Process.whereis(UserTrust) do
      UserTrust.record_interaction(user_id, tier)
    end
  end

  defp boost_queue(title, user_id) do
    if Process.whereis(GenerationQueue) do
      trust = if user_id, do: trust_multiplier(user_id), else: 1.0
      boost_amount = 2.0 * trust

      case GenerationQueue.boost(title, boost_amount) do
        {:ok, count} -> count
        _ -> 0
      end
    else
      0
    end
  end

  defp evaluate_on_demand(title) do
    if Process.whereis(OnDemand) do
      OnDemand.evaluate(title)
    end
  end

  defp enqueue_relationship_exploration(source_id, target_id, edge_type, description) do
    if Process.whereis(GenerationQueue) do
      suggested_title = description || "Relationship: #{edge_type}"

      gap = %{
        gap_type: :edge_assertion,
        priority: 6.0,
        suggested_title: suggested_title,
        context: %{node_a_id: source_id, node_b_id: target_id}
      }

      GenerationQueue.enqueue(gap)
    end
  end

  defp trigger_confidence_review(node_id, graph_repo) do
    Task.start(fn ->
      Updater.recalculate_subgraph(node_id, graph_repo, hops: 1)
    end)
  end

  defp trust_multiplier(user_id) do
    if Process.whereis(UserTrust) do
      UserTrust.trust_score(user_id)
    else
      0.5
    end
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
