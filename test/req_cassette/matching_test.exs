defmodule ReqCassette.MatchingTest do
  use ExUnit.Case, async: true

  import ReqCassette

  alias Plug.Conn

  @cassette_dir "test/fixtures/matching"

  setup do
    File.rm_rf!(@cassette_dir)
    File.mkdir_p!(@cassette_dir)
    :ok
  end

  describe "match_requests_on: [:method, :uri]" do
    test "ignores query string differences" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/search", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{query: conn.query_string}))
      end)

      # Record with one query string
      with_cassette(
        "search",
        [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri]],
        fn plug ->
          Req.get!("http://localhost:#{bypass.port}/search?q=first", plug: plug)
        end
      )

      Bypass.down(bypass)

      # Replay with different query string (should still match)
      result =
        with_cassette(
          "search",
          [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri]],
          fn plug ->
            Req.get!("http://localhost:#{bypass.port}/search?q=second", plug: plug)
          end
        )

      # Should get the recorded response (with first query)
      assert result.status == 200
    end

    test "ignores request body differences" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/api", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{received: "first"}))
      end)

      # Record with one body
      with_cassette(
        "post_api",
        [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri]],
        fn plug ->
          Req.post!(
            "http://localhost:#{bypass.port}/api",
            json: %{data: "first"},
            plug: plug
          )
        end
      )

      Bypass.down(bypass)

      # Replay with different body (should still match)
      result =
        with_cassette(
          "post_api",
          [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri]],
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/api",
              json: %{data: "second"},
              plug: plug
            )
          end
        )

      assert result.status == 200
      assert result.body["received"] == "first"
    end
  end

  describe "match_requests_on: [:method, :uri, :query]" do
    test "matches requests with same query parameters regardless of order" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/products", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{results: ["a", "b"]}))
      end)

      # Record with query params in one order
      with_cassette(
        "products",
        [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :query]],
        fn plug ->
          Req.get!("http://localhost:#{bypass.port}/products?sort=name&filter=active",
            plug: plug
          )
        end
      )

      Bypass.down(bypass)

      # Replay with query params in different order (should match)
      result =
        with_cassette(
          "products",
          [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :query]],
          fn plug ->
            Req.get!("http://localhost:#{bypass.port}/products?filter=active&sort=name",
              plug: plug
            )
          end
        )

      assert result.status == 200
      assert result.body["results"] == ["a", "b"]
    end

    test "does not match requests with different query values" do
      bypass = Bypass.open()

      Bypass.expect(bypass, "GET", "/data", fn conn ->
        # Parse query and return different responses
        query = Conn.fetch_query_params(conn).query_params

        response =
          if query["id"] == "1" do
            %{data: "one"}
          else
            %{data: "two"}
          end

        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(response))
      end)

      # Record with id=1
      with_cassette(
        "query_data",
        [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :query]],
        fn plug ->
          Req.get!("http://localhost:#{bypass.port}/data?id=1", plug: plug)
        end
      )

      # Request with id=2 (should not match, will record new interaction)
      result =
        with_cassette(
          "query_data",
          [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :query]],
          fn plug ->
            Req.get!("http://localhost:#{bypass.port}/data?id=2", plug: plug)
          end
        )

      assert result.body["data"] == "two"

      # Verify cassette has 2 interactions
      cassette_path = Path.join(@cassette_dir, "query_data.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)
      assert length(cassette["interactions"]) == 2
    end
  end

  describe "match_requests_on: [:method, :uri, :body]" do
    test "matches requests with same JSON body regardless of key order" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/create", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(201, Jason.encode!(%{id: 1, status: "created"}))
      end)

      # Record with keys in one order
      with_cassette(
        "create_order",
        [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :body]],
        fn plug ->
          Req.post!(
            "http://localhost:#{bypass.port}/create",
            json: %{name: "Alice", email: "alice@example.com"},
            plug: plug
          )
        end
      )

      Bypass.down(bypass)

      # Replay with keys in different order (should match)
      result =
        with_cassette(
          "create_order",
          [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :body]],
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/create",
              json: %{email: "alice@example.com", name: "Alice"},
              plug: plug
            )
          end
        )

      assert result.status == 201
      assert result.body["id"] == 1
    end

    test "does not match requests with different body values" do
      bypass = Bypass.open()

      Bypass.expect(bypass, "POST", "/submit", fn conn ->
        {:ok, body, conn} = Conn.read_body(conn)
        data = Jason.decode!(body)

        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{received: data["value"]}))
      end)

      # Record with value="first"
      with_cassette(
        "submit",
        [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :body]],
        fn plug ->
          Req.post!(
            "http://localhost:#{bypass.port}/submit",
            json: %{value: "first"},
            plug: plug
          )
        end
      )

      # Request with value="second" (should not match)
      result =
        with_cassette(
          "submit",
          [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :body]],
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/submit",
              json: %{value: "second"},
              plug: plug
            )
          end
        )

      assert result.body["received"] == "second"

      # Verify 2 interactions
      cassette_path = Path.join(@cassette_dir, "submit.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)
      assert length(cassette["interactions"]) == 2
    end
  end

  describe "default matching (all criteria)" do
    test "requires exact match on all fields by default" do
      bypass = Bypass.open()

      Bypass.expect(bypass, "POST", "/exact", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{matched: true}))
      end)

      # Record exact request
      with_cassette("exact", [cassette_dir: @cassette_dir], fn plug ->
        Req.post!(
          "http://localhost:#{bypass.port}/exact?param=value",
          json: %{key: "value"},
          headers: [{"x-custom", "header"}],
          plug: plug
        )
      end)

      # Try with missing header (should not match)
      result =
        with_cassette("exact", [cassette_dir: @cassette_dir], fn plug ->
          Req.post!(
            "http://localhost:#{bypass.port}/exact?param=value",
            json: %{key: "value"},
            plug: plug
          )
        end)

      assert result.status == 200

      # Verify 2 interactions (different headers)
      cassette_path = Path.join(@cassette_dir, "exact.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)
      assert length(cassette["interactions"]) == 2
    end
  end

  describe "edge cases" do
    test "handles empty query strings" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/no-query", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{data: "ok"}))
      end)

      with_cassette(
        "no_query",
        [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :query]],
        fn plug ->
          Req.get!("http://localhost:#{bypass.port}/no-query", plug: plug)
        end
      )

      Bypass.down(bypass)

      # Should match even with explicit empty query string
      result =
        with_cassette(
          "no_query",
          [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :query]],
          fn plug ->
            Req.get!("http://localhost:#{bypass.port}/no-query?", plug: plug)
          end
        )

      assert result.status == 200
    end

    test "handles empty request bodies" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/empty-body", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{status: "ok"}))
      end)

      with_cassette(
        "empty_body",
        [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :body]],
        fn plug ->
          Req.post!("http://localhost:#{bypass.port}/empty-body", plug: plug)
        end
      )

      Bypass.down(bypass)

      result =
        with_cassette(
          "empty_body",
          [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri, :body]],
          fn plug ->
            Req.post!("http://localhost:#{bypass.port}/empty-body", body: "", plug: plug)
          end
        )

      assert result.status == 200
    end
  end
end
