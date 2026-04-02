defmodule Palimpedia.Generation.RevisionPipeline do
  @moduledoc """
  Automated revision pipeline.

  Triggered by contradictions or anchor updates, regenerates affected
  documents with updated subgraph context and records revision history.
  """

  alias Palimpedia.Generation.{Pipeline, RevisionHistory}
  alias Palimpedia.Confidence.{Contradiction, Updater}

  require Logger

  @type revision_result :: %{
          node_id: integer(),
          trigger: atom(),
          success: boolean(),
          revision_id: String.t() | nil,
          error: term() | nil
        }

  @doc """
  Processes all open contradictions: for each, regenerates the lower-confidence
  node with updated subgraph context and records the revision.
  """
  def process_contradictions(opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    case Contradiction.list_open() do
      {:ok, contradictions} ->
        results =
          Enum.map(contradictions, fn c ->
            revise_for_contradiction(c, graph_repo, opts)
          end)

        succeeded = Enum.count(results, & &1.success)
        Logger.info("Contradiction revisions: #{succeeded}/#{length(results)} succeeded")
        {:ok, results}

      error ->
        {:error, error}
    end
  end

  @doc """
  Revises a single node by regenerating it with updated subgraph context.
  Records the revision in history.
  """
  def revise_node(node_id, trigger, opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    case graph_repo.get_node(node_id) do
      {:ok, old_node} ->
        old_content = old_node.content
        old_confidence = old_node.confidence

        case Pipeline.generate_from_graph(old_node.title, node_id, opts) do
          {:ok, result} ->
            record_revision(
              node_id,
              old_node.title,
              trigger,
              old_content,
              result.node.content,
              old_confidence,
              result.node.confidence
            )

            %{node_id: node_id, trigger: trigger, success: true, revision_id: nil, error: nil}

          {:error, reason} ->
            Logger.warning("Revision failed for node #{node_id}: #{inspect(reason)}")
            %{node_id: node_id, trigger: trigger, success: false, revision_id: nil, error: reason}
        end

      {:error, :not_found} ->
        %{node_id: node_id, trigger: trigger, success: false, revision_id: nil, error: :not_found}
    end
  end

  @doc """
  Revises all nodes within N hops of an updated anchor.
  Called after anchor corpus re-ingestion.
  """
  def revise_from_anchor(anchor_node_id, opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())
    hops = Keyword.get(opts, :hops, 2)

    case graph_repo.subgraph(anchor_node_id, hops) do
      {:ok, nodes, _edges} ->
        generated = Enum.filter(nodes, &(&1.node_type != :anchor))

        results =
          Enum.map(generated, fn node ->
            revise_node(node.id, :anchor_update, opts)
          end)

        # Also recalculate confidence
        Updater.recalculate_subgraph(anchor_node_id, graph_repo, hops: hops)

        succeeded = Enum.count(results, & &1.success)
        Logger.info("Anchor revision cascade: #{succeeded}/#{length(results)} nodes revised")
        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Private ---

  defp revise_for_contradiction(contradiction, graph_repo, opts) do
    # Revise the lower-confidence node
    {node_to_revise, _other} =
      case {graph_repo.get_node(contradiction.node_a_id),
            graph_repo.get_node(contradiction.node_b_id)} do
        {{:ok, a}, {:ok, b}} ->
          if a.confidence <= b.confidence, do: {a, b}, else: {b, a}

        {{:ok, a}, _} ->
          {a, nil}

        {_, {:ok, b}} ->
          {b, nil}

        _ ->
          {nil, nil}
      end

    if node_to_revise && node_to_revise.node_type != :anchor do
      result = revise_node(node_to_revise.id, :contradiction, opts)

      # Resolve the contradiction after revision
      if result.success do
        Contradiction.resolve(contradiction.id, :confirmed)
      end

      result
    else
      %{
        node_id: nil,
        trigger: :contradiction,
        success: false,
        revision_id: nil,
        error: :no_revisable_node
      }
    end
  end

  defp record_revision(node_id, title, trigger, old_content, new_content, old_conf, new_conf) do
    if Process.whereis(RevisionHistory) do
      RevisionHistory.record(
        node_id,
        title,
        trigger,
        old_content,
        new_content,
        old_conf,
        new_conf
      )
    end
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
