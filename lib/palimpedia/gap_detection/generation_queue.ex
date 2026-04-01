defmodule Palimpedia.GapDetection.GenerationQueue do
  @moduledoc """
  Priority queue for documents that need to be generated.

  Entries are scored by: relational pressure + user demand + confidence delta.
  The queue feeds the generation pipeline (Layer 3).
  """

  @type queue_entry :: %{
          id: String.t() | nil,
          gap_type: atom(),
          priority: float(),
          context_node_ids: [String.t()],
          suggested_title: String.t() | nil,
          requested_by: [String.t()],
          inserted_at: DateTime.t()
        }

  @doc "Enqueues a gap for document generation."
  @callback enqueue(map()) :: {:ok, queue_entry()} | {:error, term()}

  @doc "Pops the highest-priority entry from the queue."
  @callback dequeue() :: {:ok, queue_entry()} | {:ok, :empty}

  @doc "Returns the current queue length."
  @callback queue_length() :: non_neg_integer()

  @doc "Boosts priority for entries matching a user demand signal."
  @callback boost_priority(String.t(), float()) :: :ok | {:error, term()}
end
