defmodule Palimpedia.Anchor.WikidataAdapterTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Anchor.WikidataAdapter

  @q42_response Jason.encode!(%{
                  "entities" => %{
                    "Q42" => %{
                      "type" => "item",
                      "id" => "Q42",
                      "labels" => %{
                        "en" => %{"language" => "en", "value" => "Douglas Adams"}
                      },
                      "descriptions" => %{
                        "en" => %{
                          "language" => "en",
                          "value" => "English author and humourist (1952–2001)"
                        }
                      },
                      "claims" => %{
                        "P31" => [
                          %{
                            "mainsnak" => %{
                              "snaktype" => "value",
                              "property" => "P31",
                              "datavalue" => %{
                                "value" => %{"entity-type" => "item", "id" => "Q5"},
                                "type" => "wikibase-entityid"
                              }
                            },
                            "type" => "statement",
                            "rank" => "normal"
                          }
                        ],
                        "P737" => [
                          %{
                            "mainsnak" => %{
                              "snaktype" => "value",
                              "property" => "P737",
                              "datavalue" => %{
                                "value" => %{"entity-type" => "item", "id" => "Q544"},
                                "type" => "wikibase-entityid"
                              }
                            },
                            "type" => "statement",
                            "rank" => "normal"
                          }
                        ]
                      }
                    }
                  }
                })

  @multi_entity_response Jason.encode!(%{
                           "entities" => %{
                             "Q42" => %{
                               "type" => "item",
                               "id" => "Q42",
                               "labels" => %{
                                 "en" => %{"language" => "en", "value" => "Douglas Adams"}
                               },
                               "descriptions" => %{
                                 "en" => %{
                                   "language" => "en",
                                   "value" => "English author"
                                 }
                               },
                               "claims" => %{}
                             },
                             "Q5" => %{
                               "type" => "item",
                               "id" => "Q5",
                               "labels" => %{
                                 "en" => %{"language" => "en", "value" => "human"}
                               },
                               "descriptions" => %{
                                 "en" => %{
                                   "language" => "en",
                                   "value" => "common name of Homo sapiens"
                                 }
                               },
                               "claims" => %{}
                             }
                           }
                         })

  @search_response Jason.encode!(%{
                     "search" => [
                       %{"id" => "Q42", "label" => "Douglas Adams"},
                       %{"id" => "Q5", "label" => "human"}
                     ]
                   })

  defp mock_http(response_body, expected_status \\ 200) do
    fn _url, _opts ->
      {:ok, %{status: expected_status, body: response_body, headers: []}}
    end
  end

  describe "fetch_entity/2" do
    test "fetches and parses a single Wikidata entity" do
      assert {:ok, result} =
               WikidataAdapter.fetch_entity("Q42", http_client: mock_http(@q42_response))

      assert length(result.entities) == 1

      [entity] = result.entities
      assert entity.title == "Douglas Adams"
      assert entity.content == "English author and humourist (1952–2001)"
      assert entity.source_id == "wikidata:Q42"
      assert entity.properties.qid == "Q42"
    end

    test "extracts inter-entity relationships from claims" do
      assert {:ok, result} =
               WikidataAdapter.fetch_entity("Q42", http_client: mock_http(@q42_response))

      # P31 (instance of) -> :specializes, P737 (influenced by) -> :influences
      assert length(result.relationships) == 2

      edge_types = Enum.map(result.relationships, & &1.edge_type) |> MapSet.new()
      assert :specializes in edge_types
      assert :influences in edge_types

      # Check source/target IDs
      specializes_rel = Enum.find(result.relationships, &(&1.edge_type == :specializes))
      assert specializes_rel.source_id == "wikidata:Q42"
      assert specializes_rel.target_id == "wikidata:Q5"
      assert specializes_rel.confidence == 1.0
    end
  end

  describe "fetch_entities/2" do
    test "fetches multiple entities in a single request" do
      assert {:ok, result} =
               WikidataAdapter.fetch_entities(["Q42", "Q5"],
                 http_client: mock_http(@multi_entity_response)
               )

      assert length(result.entities) == 2
      titles = Enum.map(result.entities, & &1.title) |> MapSet.new()
      assert "Douglas Adams" in titles
      assert "human" in titles
    end

    test "handles missing entities gracefully" do
      response_with_missing =
        Jason.encode!(%{
          "entities" => %{
            "Q42" => %{
              "type" => "item",
              "id" => "Q42",
              "labels" => %{"en" => %{"language" => "en", "value" => "Douglas Adams"}},
              "descriptions" => %{"en" => %{"language" => "en", "value" => "Author"}},
              "claims" => %{}
            },
            "Q99999999" => %{"id" => "Q99999999", "missing" => ""}
          }
        })

      assert {:ok, result} =
               WikidataAdapter.fetch_entities(["Q42", "Q99999999"],
                 http_client: mock_http(response_with_missing)
               )

      assert length(result.entities) == 1
      assert hd(result.entities).title == "Douglas Adams"
    end
  end

  describe "search/2" do
    test "searches and fetches matching entities" do
      # search returns QIDs, then fetch_entities is called
      call_count = :counters.new(1, [:atomics])

      mock_fn = fn _url, _opts ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        body =
          if count == 1 do
            @search_response
          else
            @multi_entity_response
          end

        {:ok, %{status: 200, body: body, headers: []}}
      end

      assert {:ok, result} = WikidataAdapter.search("Douglas Adams", http_client: mock_fn)
      assert length(result.entities) == 2
    end
  end

  describe "error handling" do
    test "returns error on HTTP failure" do
      mock_fn = fn _url, _opts -> {:error, :timeout} end

      assert {:error, :timeout} =
               WikidataAdapter.fetch_entity("Q42", http_client: mock_fn)
    end

    test "returns error on non-200 status" do
      assert {:error, {:http_error, 429}} =
               WikidataAdapter.fetch_entity("Q42", http_client: mock_http("", 429))
    end

    test "returns error on invalid JSON" do
      assert {:error, {:json_parse_error, _}} =
               WikidataAdapter.fetch_entity("Q42", http_client: mock_http("not json"))
    end
  end

  describe "property_edge_mapping/0" do
    test "contains expected Wikidata property mappings" do
      mapping = WikidataAdapter.property_edge_mapping()

      assert mapping["P31"] == :specializes
      assert mapping["P279"] == :generalizes
      assert mapping["P737"] == :influences
      assert mapping["P461"] == :contradicts
    end
  end
end
