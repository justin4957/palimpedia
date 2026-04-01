defmodule Palimpedia.Interaction.UserInput do
  @moduledoc """
  Three tiers of epistemic input from users.

  Users are graph participants — sources of structural intuition
  that the automated system cannot supply.
  """

  @type tier :: :node_request | :edge_assertion | :contradiction_flag

  @type input :: %{
          tier: tier(),
          payload: map(),
          user_id: String.t() | nil,
          timestamp: DateTime.t()
        }

  @doc "Creates a Tier 1 node request — a demand signal for document generation."
  def node_request(title, opts \\ []) do
    %{
      tier: :node_request,
      payload: %{title: title, metadata: Keyword.get(opts, :metadata, %{})},
      user_id: Keyword.get(opts, :user_id),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a Tier 2 edge assertion — a relational claim.
  "X connects to Y via mechanism Z."
  """
  def edge_assertion(source_title, target_title, relationship, opts \\ []) do
    %{
      tier: :edge_assertion,
      payload: %{
        source: source_title,
        target: target_title,
        relationship: relationship,
        description: Keyword.get(opts, :description)
      },
      user_id: Keyword.get(opts, :user_id),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a Tier 3 contradiction flag — triggers structural review.
  "Document A is inconsistent with Document B."
  """
  def contradiction_flag(node_a_id, node_b_id, description, opts \\ []) do
    %{
      tier: :contradiction_flag,
      payload: %{
        node_a_id: node_a_id,
        node_b_id: node_b_id,
        description: description
      },
      user_id: Keyword.get(opts, :user_id),
      timestamp: DateTime.utc_now()
    }
  end
end
