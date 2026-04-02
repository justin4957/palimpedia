defmodule Palimpedia.Deployment.ConfigTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Deployment.Config
  alias Palimpedia.Graph.Node

  setup do
    original = Application.get_env(:palimpedia, Config)
    on_exit(fn -> Application.put_env(:palimpedia, Config, original || []) end)
    :ok
  end

  describe "mode/0" do
    test "defaults to :standard" do
      Application.put_env(:palimpedia, Config, [])
      assert Config.mode() == :standard
    end

    test "reads from config" do
      Application.put_env(:palimpedia, Config, mode: :air_gapped)
      assert Config.mode() == :air_gapped
    end
  end

  describe "federation_enabled?/0" do
    test "enabled in standard mode" do
      Application.put_env(:palimpedia, Config, mode: :standard)
      assert Config.federation_enabled?() == true
    end

    test "disabled in air_gapped mode" do
      Application.put_env(:palimpedia, Config, mode: :air_gapped)
      assert Config.federation_enabled?() == false
    end

    test "configurable in restricted mode" do
      Application.put_env(:palimpedia, Config, mode: :restricted, federation_enabled: false)
      assert Config.federation_enabled?() == false
    end
  end

  describe "external_apis_allowed?/0" do
    test "allowed in standard mode" do
      Application.put_env(:palimpedia, Config, mode: :standard)
      assert Config.external_apis_allowed?() == true
    end

    test "blocked in air_gapped mode" do
      Application.put_env(:palimpedia, Config, mode: :air_gapped)
      assert Config.external_apis_allowed?() == false
    end
  end

  describe "proprietary?/1" do
    test "identifies proprietary nodes by provenance labels" do
      Application.put_env(:palimpedia, Config, proprietary_labels: ["classified", "internal"])

      proprietary_node = %Node{
        id: 1,
        title: "Secret Doc",
        node_type: :anchor,
        provenance: ["classified:doc-001"]
      }

      public_node = %Node{
        id: 2,
        title: "Public Doc",
        node_type: :anchor,
        provenance: ["wikidata:Q944"]
      }

      assert Config.proprietary?(proprietary_node) == true
      assert Config.proprietary?(public_node) == false
    end

    test "returns false when no proprietary labels configured" do
      Application.put_env(:palimpedia, Config, proprietary_labels: [])

      node = %Node{id: 1, title: "Any", node_type: :anchor, provenance: ["classified:x"]}
      assert Config.proprietary?(node) == false
    end
  end

  describe "summary/0" do
    test "returns full deployment info" do
      Application.put_env(:palimpedia, Config, mode: :air_gapped, llm_provider: :ollama)

      summary = Config.summary()
      assert summary.mode == :air_gapped
      assert summary.llm_provider == :ollama
      assert summary.federation_enabled == false
      assert summary.external_apis_allowed == false
    end
  end
end
