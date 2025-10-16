defmodule ReqCassette.WithCassetteTest do
  use ExUnit.Case, async: true

  import ReqCassette

  alias Plug.Conn

  @cassette_dir "test/fixtures/with_cassette"

  setup do
    # Clean up cassettes before each test
    File.rm_rf!(@cassette_dir)
    File.mkdir_p!(@cassette_dir)
    :ok
  end

  describe "with_cassette/3" do
    test "records and replays a simple request" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/data", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{message: "Hello"}))
      end)

      # First call - records
      result1 =
        with_cassette("simple_request", [cassette_dir: @cassette_dir], fn plug ->
          Req.get!("http://localhost:#{bypass.port}/data", plug: plug)
        end)

      assert result1.status == 200
      assert result1.body["message"] == "Hello"

      # Verify cassette was created
      cassettes = File.ls!(@cassette_dir)
      assert length(cassettes) == 1
      assert "simple_request.json" in cassettes

      # Take down bypass to ensure replay works
      Bypass.down(bypass)

      # Second call - replays from cassette
      result2 =
        with_cassette("simple_request", [cassette_dir: @cassette_dir], fn plug ->
          Req.get!("http://localhost:#{bypass.port}/data", plug: plug)
        end)

      assert result2.status == 200
      assert result2.body["message"] == "Hello"
    end

    test "returns the function's return value" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/user", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{id: 1, name: "Alice"}))
      end)

      # Test that the function's return value is preserved
      {status, body} =
        with_cassette("user_data", [cassette_dir: @cassette_dir], fn plug ->
          response = Req.get!("http://localhost:#{bypass.port}/user", plug: plug)
          {response.status, response.body}
        end)

      assert status == 200
      assert body["id"] == 1
      assert body["name"] == "Alice"
    end

    test "works without opts argument" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/hello", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{greeting: "Hi"}))
      end)

      # Call with minimal opts (cassette_dir only)
      result =
        with_cassette("no_opts", [cassette_dir: @cassette_dir], fn plug ->
          Req.get!("http://localhost:#{bypass.port}/hello", plug: plug)
        end)

      assert result.status == 200
      assert result.body["greeting"] == "Hi"
    end

    test "supports mode: :replay" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/api", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{data: "test"}))
      end)

      # First - record
      with_cassette("replay_test", [cassette_dir: @cassette_dir], fn plug ->
        Req.get!("http://localhost:#{bypass.port}/api", plug: plug)
      end)

      Bypass.down(bypass)

      # Second - replay with explicit mode
      result =
        with_cassette(
          "replay_test",
          [cassette_dir: @cassette_dir, mode: :replay],
          fn plug ->
            Req.get!("http://localhost:#{bypass.port}/api", plug: plug)
          end
        )

      assert result.status == 200
      assert result.body["data"] == "test"
    end

    test "supports mode: :bypass" do
      bypass = Bypass.open()

      # Expect to be called twice (bypass mode always hits network)
      Bypass.expect(bypass, "GET", "/bypass", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{mode: "bypass"}))
      end)

      # First call - bypass mode (doesn't create cassette)
      with_cassette(
        "bypass_test",
        [cassette_dir: @cassette_dir, mode: :bypass],
        fn plug ->
          Req.get!("http://localhost:#{bypass.port}/bypass", plug: plug)
        end
      )

      # Verify no cassette was created
      cassettes = File.ls!(@cassette_dir)
      assert length(cassettes) == 0

      # Second call - also hits network
      result =
        with_cassette(
          "bypass_test",
          [cassette_dir: @cassette_dir, mode: :bypass],
          fn plug ->
            Req.get!("http://localhost:#{bypass.port}/bypass", plug: plug)
          end
        )

      assert result.status == 200
      assert result.body["mode"] == "bypass"
    end

    test "supports custom match_requests_on" do
      bypass = Bypass.open()

      Bypass.expect(bypass, "POST", "/match", fn conn ->
        {:ok, body, conn} = Conn.read_body(conn)
        data = Jason.decode!(body)

        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{received: data["value"]}))
      end)

      # First request - record
      with_cassette(
        "custom_match",
        [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri]],
        fn plug ->
          Req.post!(
            "http://localhost:#{bypass.port}/match",
            json: %{value: "first"},
            plug: plug
          )
        end
      )

      Bypass.down(bypass)

      # Second request with different body - should replay first one
      # because we're only matching on method and uri
      result =
        with_cassette(
          "custom_match",
          [cassette_dir: @cassette_dir, match_requests_on: [:method, :uri]],
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/match",
              json: %{value: "second"},
              plug: plug
            )
          end
        )

      # Should get the first response back
      assert result.status == 200
      assert result.body["received"] == "first"
    end

    test "supports nested cassettes" do
      bypass1 = Bypass.open()
      bypass2 = Bypass.open()

      Bypass.expect_once(bypass1, "GET", "/api1", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{source: "api1"}))
      end)

      Bypass.expect_once(bypass2, "GET", "/api2", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{source: "api2"}))
      end)

      # Nested cassettes with different names
      {resp1, resp2} =
        with_cassette("outer", [cassette_dir: @cassette_dir], fn outer_plug ->
          r1 = Req.get!("http://localhost:#{bypass1.port}/api1", plug: outer_plug)

          with_cassette("inner", [cassette_dir: @cassette_dir], fn inner_plug ->
            r2 = Req.get!("http://localhost:#{bypass2.port}/api2", plug: inner_plug)
            {r1, r2}
          end)
        end)

      assert resp1.body["source"] == "api1"
      assert resp2.body["source"] == "api2"

      # Verify both cassettes were created
      cassettes = File.ls!(@cassette_dir)
      assert length(cassettes) == 2
      assert "outer.json" in cassettes
      assert "inner.json" in cassettes
    end

    test "can be used with helper functions" do
      # Helper function that accepts a plug option
      fetch_user = fn id, opts ->
        plug = opts[:plug]
        bypass = opts[:bypass]

        Req.get!("http://localhost:#{bypass.port}/users/#{id}", plug: plug)
      end

      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/users/42", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{id: 42, name: "Helper User"}))
      end)

      # Use with_cassette to pass plug to helper function
      result =
        with_cassette("helper_test", [cassette_dir: @cassette_dir], fn plug ->
          fetch_user.(42, plug: plug, bypass: bypass)
        end)

      assert result.status == 200
      assert result.body["id"] == 42
      assert result.body["name"] == "Helper User"
    end
  end
end
