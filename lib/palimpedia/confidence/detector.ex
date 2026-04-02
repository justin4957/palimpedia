defmodule Palimpedia.Confidence.Detector do
  @moduledoc """
  Automated contradiction detection.

  Compares claims across linked documents to find conflicting assertions.
  Uses simple heuristics (negation patterns, conflicting dates/numbers)
  to flag potential contradictions for review.
  """

  alias Palimpedia.Confidence.{Contradiction, Scorer}

  require Logger

  @negation_pairs [
    {"is", "is not"},
    {"was", "was not"},
    {"can", "cannot"},
    {"does", "does not"},
    {"has", "has no"},
    {"supports", "contradicts"},
    {"proves", "disproves"},
    {"confirms", "refutes"},
    {"true", "false"},
    {"valid", "invalid"},
    {"possible", "impossible"},
    {"compatible", "incompatible"}
  ]

  @doc """
  Checks two nodes for contradictions by comparing their content.
  If contradictions are found, flags them in the ContradictionStore
  and returns the list of detected contradictions.
  """
  def check_pair(node_a, node_b) do
    content_a = node_a.content || ""
    content_b = node_b.content || ""

    if content_a == "" or content_b == "" do
      {:ok, []}
    else
      contradictions = find_contradictions(content_a, content_b)

      flagged =
        Enum.map(contradictions, fn {description, severity} ->
          if Process.whereis(Contradiction) do
            case Contradiction.flag(node_a.id, node_b.id, description,
                   severity: severity,
                   flagged_by: :system
                 ) do
              {:ok, c} -> c
              _ -> nil
            end
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, flagged}
    end
  end

  @doc """
  Checks a node against all its neighbors for contradictions.
  """
  def check_neighborhood(node_id, graph_repo) do
    with {:ok, nodes, _edges} <- graph_repo.subgraph(node_id, 1) do
      center = Enum.find(nodes, &(&1.id == node_id))
      neighbors = Enum.reject(nodes, &(&1.id == node_id))

      if is_nil(center) do
        {:ok, []}
      else
        all_contradictions =
          Enum.flat_map(neighbors, fn neighbor ->
            case check_pair(center, neighbor) do
              {:ok, contradictions} -> contradictions
              _ -> []
            end
          end)

        {:ok, all_contradictions}
      end
    end
  end

  @doc """
  Applies confidence penalties for all open contradictions on a node.
  Returns the penalized confidence score.
  """
  def apply_penalties(node_id, base_confidence) do
    count =
      if Process.whereis(Contradiction) do
        Contradiction.count_for_node(node_id)
      else
        0
      end

    Scorer.apply_contradiction_penalty(base_confidence, count)
  end

  # --- Private ---

  defp find_contradictions(content_a, content_b) do
    sentences_a = extract_sentences(content_a)
    sentences_b = extract_sentences(content_b)

    negation_contradictions = detect_negation_patterns(sentences_a, sentences_b)
    number_contradictions = detect_number_conflicts(sentences_a, sentences_b)

    negation_contradictions ++ number_contradictions
  end

  defp detect_negation_patterns(sentences_a, sentences_b) do
    for sent_a <- sentences_a,
        sent_b <- sentences_b,
        {pos, neg} <- @negation_pairs,
        contradiction = check_negation(sent_a, sent_b, pos, neg),
        contradiction != nil do
      contradiction
    end
    |> Enum.uniq_by(fn {desc, _} -> desc end)
    |> Enum.take(5)
  end

  defp check_negation(sent_a, sent_b, positive, negative) do
    lower_a = String.downcase(sent_a)
    lower_b = String.downcase(sent_b)

    shared_subject = find_shared_subject(lower_a, lower_b)

    cond do
      shared_subject != nil and String.contains?(lower_a, positive) and
          String.contains?(lower_b, negative) ->
        description =
          "Potential contradiction about '#{shared_subject}': " <>
            "one document states '#{positive}' while another states '#{negative}'"

        {description, :medium}

      shared_subject != nil and String.contains?(lower_a, negative) and
          String.contains?(lower_b, positive) ->
        description =
          "Potential contradiction about '#{shared_subject}': " <>
            "one document states '#{negative}' while another states '#{positive}'"

        {description, :medium}

      true ->
        nil
    end
  end

  defp detect_number_conflicts(sentences_a, sentences_b) do
    for sent_a <- sentences_a,
        sent_b <- sentences_b,
        conflict = check_number_conflict(sent_a, sent_b),
        conflict != nil do
      conflict
    end
    |> Enum.uniq_by(fn {desc, _} -> desc end)
    |> Enum.take(3)
  end

  defp check_number_conflict(sent_a, sent_b) do
    # Look for sentences about the same subject with different year/number values
    numbers_a = Regex.scan(~r/\b(\d{4})\b/, sent_a) |> Enum.map(fn [_, n] -> n end)
    numbers_b = Regex.scan(~r/\b(\d{4})\b/, sent_b) |> Enum.map(fn [_, n] -> n end)

    shared_subject = find_shared_subject(String.downcase(sent_a), String.downcase(sent_b))

    if shared_subject != nil and numbers_a != [] and numbers_b != [] do
      conflicting = numbers_a -- numbers_b

      if conflicting != [] and length(numbers_a) <= 2 and length(numbers_b) <= 2 do
        {"Conflicting dates/numbers about '#{shared_subject}': #{Enum.join(numbers_a, ", ")} vs #{Enum.join(numbers_b, ", ")}",
         :low}
      else
        nil
      end
    else
      nil
    end
  end

  defp find_shared_subject(text_a, text_b) do
    words_a = significant_words(text_a)
    words_b = significant_words(text_b)

    common = MapSet.intersection(words_a, words_b)

    if MapSet.size(common) >= 2 do
      common |> MapSet.to_list() |> Enum.take(3) |> Enum.join(" ")
    else
      nil
    end
  end

  defp significant_words(text) do
    stop_words =
      MapSet.new(~w(the a an is are was were be been being have has had do does did
        will would shall should may might can could of in on at to for with by from
        as into through during before after above below between out about not no nor
        and or but if then else when where how what which who whom this that these those
        it its he she they them their we our you your))

    text
    |> String.split(~r/[^a-z0-9]+/)
    |> Enum.filter(fn w -> String.length(w) > 2 and w not in stop_words end)
    |> MapSet.new()
  end

  defp extract_sentences(text) do
    text
    |> String.split(~r/[.!?\n]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
