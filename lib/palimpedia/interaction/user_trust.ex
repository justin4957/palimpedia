defmodule Palimpedia.Interaction.UserTrust do
  @moduledoc """
  User trust scoring based on interaction history.

  Trust is calibrated by tier and tracks provenance:
  - Tier 1 (node requests): Low trust, crawler-equivalent
  - Tier 2 (edge assertions): Medium trust, relational claims
  - Tier 3 (contradiction flags): High trust, structural review

  Trust scores affect how the system weights user inputs.
  Higher trust = greater influence on generation priority.
  """

  use GenServer

  @type user_profile :: %{
          user_id: String.t(),
          trust_score: float(),
          total_interactions: non_neg_integer(),
          tier_counts: %{
            node_request: non_neg_integer(),
            edge_assertion: non_neg_integer(),
            contradiction_flag: non_neg_integer()
          },
          approved_contributions: non_neg_integer(),
          rejected_contributions: non_neg_integer(),
          last_active_at: DateTime.t()
        }

  @initial_trust 0.5
  @tier_trust_weights %{node_request: 0.01, edge_assertion: 0.03, contradiction_flag: 0.05}
  @approval_boost 0.05
  @rejection_penalty 0.1

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Records a user interaction and updates trust score."
  def record_interaction(user_id, tier)
      when tier in [:node_request, :edge_assertion, :contradiction_flag] do
    GenServer.call(__MODULE__, {:record, user_id, tier})
  end

  @doc "Records that a user's contribution was approved (boosts trust)."
  def record_approval(user_id) do
    GenServer.call(__MODULE__, {:approval, user_id})
  end

  @doc "Records that a user's contribution was rejected (reduces trust)."
  def record_rejection(user_id) do
    GenServer.call(__MODULE__, {:rejection, user_id})
  end

  @doc "Returns the trust profile for a user."
  def get_profile(user_id) do
    GenServer.call(__MODULE__, {:get, user_id})
  end

  @doc "Returns the trust score for a user (0.0 to 1.0)."
  def trust_score(user_id) do
    case get_profile(user_id) do
      {:ok, profile} -> profile.trust_score
      _ -> @initial_trust
    end
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    {:ok, %{profiles: %{}}}
  end

  @impl true
  def handle_call({:record, user_id, tier}, _from, state) do
    profile = get_or_create(state, user_id)
    trust_delta = Map.get(@tier_trust_weights, tier, 0.0)

    tier_counts = Map.update(profile.tier_counts, tier, 1, &(&1 + 1))

    updated = %{
      profile
      | trust_score: clamp(profile.trust_score + trust_delta),
        total_interactions: profile.total_interactions + 1,
        tier_counts: tier_counts,
        last_active_at: DateTime.utc_now()
    }

    state = put_profile(state, user_id, updated)
    {:reply, {:ok, updated}, state}
  end

  @impl true
  def handle_call({:approval, user_id}, _from, state) do
    profile = get_or_create(state, user_id)

    updated = %{
      profile
      | trust_score: clamp(profile.trust_score + @approval_boost),
        approved_contributions: profile.approved_contributions + 1,
        last_active_at: DateTime.utc_now()
    }

    state = put_profile(state, user_id, updated)
    {:reply, {:ok, updated}, state}
  end

  @impl true
  def handle_call({:rejection, user_id}, _from, state) do
    profile = get_or_create(state, user_id)

    updated = %{
      profile
      | trust_score: clamp(profile.trust_score - @rejection_penalty),
        rejected_contributions: profile.rejected_contributions + 1,
        last_active_at: DateTime.utc_now()
    }

    state = put_profile(state, user_id, updated)
    {:reply, {:ok, updated}, state}
  end

  @impl true
  def handle_call({:get, user_id}, _from, state) do
    case Map.get(state.profiles, user_id) do
      nil -> {:reply, {:error, :not_found}, state}
      profile -> {:reply, {:ok, profile}, state}
    end
  end

  defp get_or_create(state, user_id) do
    Map.get(state.profiles, user_id, %{
      user_id: user_id,
      trust_score: @initial_trust,
      total_interactions: 0,
      tier_counts: %{node_request: 0, edge_assertion: 0, contradiction_flag: 0},
      approved_contributions: 0,
      rejected_contributions: 0,
      last_active_at: DateTime.utc_now()
    })
  end

  defp put_profile(state, user_id, profile) do
    %{state | profiles: Map.put(state.profiles, user_id, profile)}
  end

  defp clamp(value), do: max(0.0, min(1.0, value))
end
