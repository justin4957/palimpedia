defmodule PalimpediaWeb.ReviewControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  alias Palimpedia.Review.Queue, as: ReviewQueue

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)

    # Submit a test review item with a unique node ID
    unique_node_id = :erlang.unique_integer([:positive]) + 500_000
    {:ok, item} = ReviewQueue.submit(unique_node_id, "Test Node", :high_confidence)
    %{review_id: item.id, node_id: unique_node_id}
  end

  describe "GET /api/reviews" do
    test "lists pending review items", %{conn: conn} do
      conn = get(conn, "/api/reviews")
      assert %{"data" => data, "meta" => %{"count" => count}} = json_response(conn, 200)
      assert count >= 1
      assert is_list(data)
    end
  end

  describe "GET /api/reviews/stats" do
    test "returns review metrics", %{conn: conn} do
      conn = get(conn, "/api/reviews/stats")
      assert %{"data" => data} = json_response(conn, 200)
      assert Map.has_key?(data, "pending")
      assert Map.has_key?(data, "total_approved")
    end
  end

  describe "GET /api/reviews/:id" do
    test "returns a review item", %{conn: conn, review_id: review_id} do
      conn = get(conn, "/api/reviews/#{review_id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == review_id
      assert data["status"] == "pending"
    end

    test "returns 404 for unknown ID", %{conn: conn} do
      conn = get(conn, "/api/reviews/nonexistent")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/reviews/:id/approve" do
    test "approves a review item", %{conn: conn, review_id: review_id} do
      conn = post(conn, "/api/reviews/#{review_id}/approve", %{"note" => "Verified"})
      assert %{"data" => data, "meta" => meta} = json_response(conn, 200)
      assert data["status"] == "approved"
      assert data["reviewer_note"] == "Verified"
      assert meta["action"] == "approved"
    end
  end

  describe "POST /api/reviews/:id/reject" do
    test "rejects a review item", %{conn: conn} do
      {:ok, item} = ReviewQueue.submit(99, "To Reject", :manual)
      conn = post(conn, "/api/reviews/#{item.id}/reject", %{"note" => "Inaccurate"})
      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "rejected"
    end
  end

  describe "POST /api/reviews/:id/flag" do
    test "flags a review item", %{conn: conn} do
      {:ok, item} = ReviewQueue.submit(98, "To Flag", :manual)
      conn = post(conn, "/api/reviews/#{item.id}/flag", %{"note" => "Needs investigation"})
      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "flagged"
    end
  end
end
