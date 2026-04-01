defmodule Palimpedia.Generation.ResponseParserTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Generation.ResponseParser

  @valid_response Jason.encode!(%{
                    "title" => "Quantum Entanglement and Bell Inequalities",
                    "content" =>
                      "Quantum entanglement is a phenomenon where particles become correlated...",
                    "claims" => [
                      %{
                        "text" =>
                          "Bell's theorem shows that no local hidden variable theory can reproduce all predictions of quantum mechanics.",
                        "confidence" => 0.95,
                        "provenance" => ["wikidata:Q194112"]
                      },
                      %{
                        "text" => "The EPR paradox was proposed in 1935.",
                        "confidence" => 0.9,
                        "provenance" => ["wikidata:Q189737"]
                      }
                    ],
                    "edges" => [
                      %{
                        "target_title" => "Quantum Mechanics",
                        "edge_type" => "specializes",
                        "confidence" => 0.9
                      },
                      %{
                        "target_title" => "EPR Paradox",
                        "edge_type" => "contradicts",
                        "confidence" => 0.85
                      }
                    ],
                    "contradictions" => [
                      %{
                        "existing_node_title" => "Local Hidden Variables",
                        "description" =>
                          "Bell's theorem disproves the local hidden variable interpretation"
                      }
                    ]
                  })

  describe "parse/1" do
    test "parses a well-formed JSON response" do
      assert {:ok, parsed} = ResponseParser.parse(@valid_response)

      assert parsed.title == "Quantum Entanglement and Bell Inequalities"
      assert String.contains?(parsed.content, "entanglement")
    end

    test "extracts claims with confidence scores" do
      assert {:ok, parsed} = ResponseParser.parse(@valid_response)

      assert length(parsed.claims) == 2
      bell_claim = hd(parsed.claims)
      assert String.contains?(bell_claim.text, "Bell's theorem")
      assert bell_claim.confidence == 0.95
      assert "wikidata:Q194112" in bell_claim.provenance
    end

    test "extracts typed edges" do
      assert {:ok, parsed} = ResponseParser.parse(@valid_response)

      assert length(parsed.edges) == 2
      specializes = Enum.find(parsed.edges, &(&1.edge_type == :specializes))
      assert specializes.target_title == "Quantum Mechanics"
      assert specializes.confidence == 0.9
    end

    test "extracts contradictions" do
      assert {:ok, parsed} = ResponseParser.parse(@valid_response)

      assert length(parsed.contradictions) == 1
      [contradiction] = parsed.contradictions
      assert contradiction.existing_node_title == "Local Hidden Variables"
    end

    test "handles JSON in markdown code blocks" do
      wrapped = """
      Here is the generated document:

      ```json
      {"title": "Test", "content": "Some content", "claims": [], "edges": [], "contradictions": []}
      ```
      """

      assert {:ok, parsed} = ResponseParser.parse(wrapped)
      assert parsed.title == "Test"
    end

    test "handles missing optional fields" do
      minimal = Jason.encode!(%{"title" => "Minimal", "content" => "Just content"})

      assert {:ok, parsed} = ResponseParser.parse(minimal)
      assert parsed.title == "Minimal"
      assert parsed.claims == []
      assert parsed.edges == []
      assert parsed.contradictions == []
    end

    test "rejects invalid edge types" do
      response =
        Jason.encode!(%{
          "title" => "Test",
          "content" => "Content",
          "edges" => [
            %{"target_title" => "X", "edge_type" => "bogus_type", "confidence" => 0.5},
            %{"target_title" => "Y", "edge_type" => "references", "confidence" => 0.8}
          ]
        })

      assert {:ok, parsed} = ResponseParser.parse(response)
      # Only valid edge type should survive
      assert length(parsed.edges) == 1
      assert hd(parsed.edges).edge_type == :references
    end

    test "clamps confidence to 0.0-1.0 range" do
      response =
        Jason.encode!(%{
          "title" => "Test",
          "content" => "Content",
          "claims" => [
            %{"text" => "Overconfident", "confidence" => 1.5},
            %{"text" => "Negative", "confidence" => -0.5}
          ]
        })

      assert {:ok, parsed} = ResponseParser.parse(response)
      assert hd(parsed.claims).confidence == 1.0
      assert Enum.at(parsed.claims, 1).confidence == 0.0
    end

    test "returns error for missing title" do
      response = Jason.encode!(%{"content" => "No title"})
      assert {:error, {:missing_field, "title"}} = ResponseParser.parse(response)
    end

    test "returns error for missing content" do
      response = Jason.encode!(%{"title" => "No content"})
      assert {:error, {:missing_field, "content"}} = ResponseParser.parse(response)
    end

    test "returns error for non-JSON input" do
      assert {:error, {:parse_failed, _}} = ResponseParser.parse("not json at all")
    end
  end
end
