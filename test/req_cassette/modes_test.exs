defmodule ReqCassette.ModesTest do
  use ExUnit.Case, async: true

  import ReqCassette

  alias Plug.Conn

  @cassette_dir "test/fixtures/modes"

  setup do
    File.rm_rf!(@cassette_dir)
    File.mkdir_p!(@cassette_dir)
    :ok
  end

  describe "mode: :replay" do
    test "replays from existing cassette" do
      bypass = Bypass.open()

      # Record first
      Bypass.expect_once(bypass, "GET", "/api", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{mode: "replay"}))
      end)

      with_cassette("replay_mode", [cassette_dir: @cassette_dir], fn plug ->
        Req.get!("http://localhost:#{bypass.port}/api", plug: plug)
      end)

      Bypass.down(bypass)

      # Replay with explicit mode
      result =
        with_cassette(
          "replay_mode",
          [cassette_dir: @cassette_dir, mode: :replay],
          fn plug ->
            Req.get!("http://localhost:#{bypass.port}/api", plug: plug)
          end
        )

      assert result.status == 200
      assert result.body["mode"] == "replay"
    end

    test "raises error when cassette doesn't exist" do
      assert_raise RuntimeError, ~r/Cassette not found/, fn ->
        with_cassette(
          "nonexistent",
          [cassette_dir: @cassette_dir, mode: :replay],
          fn plug ->
            Req.get!("http://localhost:12345/api", plug: plug)
          end
        )
      end
    end

    test "raises error when no matching interaction found" do
      bypass = Bypass.open()

      # Record a GET request
      Bypass.expect_once(bypass, "GET", "/api", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{method: "GET"}))
      end)

      with_cassette("mismatch", [cassette_dir: @cassette_dir], fn plug ->
        Req.get!("http://localhost:#{bypass.port}/api", plug: plug)
      end)

      # Try to replay a POST request (won't match)
      assert_raise RuntimeError, ~r/No matching interaction found/, fn ->
        with_cassette(
          "mismatch",
          [cassette_dir: @cassette_dir, mode: :replay],
          fn plug ->
            Req.post!("http://localhost:#{bypass.port}/api", plug: plug)
          end
        )
      end
    end
  end

  describe "mode: :record" do
    test "always hits network and overwrites cassette" do
      bypass = Bypass.open()

      # First recording
      Bypass.expect_once(bypass, "GET", "/counter", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{count: 1}))
      end)

      with_cassette("overwrite", [cassette_dir: @cassette_dir, mode: :record], fn plug ->
        Req.get!("http://localhost:#{bypass.port}/counter", plug: plug)
      end)

      # Second recording - should overwrite
      Bypass.expect_once(bypass, "GET", "/counter", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{count: 2}))
      end)

      result =
        with_cassette("overwrite", [cassette_dir: @cassette_dir, mode: :record], fn plug ->
          Req.get!("http://localhost:#{bypass.port}/counter", plug: plug)
        end)

      # Should have the new value
      assert result.body["count"] == 2

      # Verify cassette contains the new value
      cassette_path = Path.join(@cassette_dir, "overwrite.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)

      # Should only have 1 interaction (overwritten, not appended)
      assert length(cassette["interactions"]) == 1

      assert get_in(cassette, ["interactions", Access.at(0), "response", "body_json", "count"]) ==
               2
    end

    test "raises error when network is unavailable" do
      assert_raise RuntimeError, ~r/Network request failed/, fn ->
        with_cassette(
          "network_error",
          [cassette_dir: @cassette_dir, mode: :record],
          fn plug ->
            # Port 1 should be unreachable
            Req.get!("http://localhost:1/api", plug: plug)
          end
        )
      end
    end
  end

  describe "mode: :record_missing (default)" do
    test "records on first call, replays on subsequent calls" do
      bypass = Bypass.open()

      # First call - records
      Bypass.expect_once(bypass, "GET", "/data", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{value: "original"}))
      end)

      result1 =
        with_cassette("record_missing", [cassette_dir: @cassette_dir], fn plug ->
          Req.get!("http://localhost:#{bypass.port}/data", plug: plug)
        end)

      assert result1.body["value"] == "original"

      # Take down server
      Bypass.down(bypass)

      # Second call - replays
      result2 =
        with_cassette("record_missing", [cassette_dir: @cassette_dir], fn plug ->
          Req.get!("http://localhost:#{bypass.port}/data", plug: plug)
        end)

      assert result2.body["value"] == "original"
    end

    test "appends new interactions to existing cassette" do
      bypass = Bypass.open()

      # First request
      Bypass.expect_once(bypass, "GET", "/item/1", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{id: 1}))
      end)

      with_cassette("append", [cassette_dir: @cassette_dir], fn plug ->
        Req.get!("http://localhost:#{bypass.port}/item/1", plug: plug)
      end)

      # Second request (different path)
      Bypass.expect_once(bypass, "GET", "/item/2", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{id: 2}))
      end)

      with_cassette("append", [cassette_dir: @cassette_dir], fn plug ->
        Req.get!("http://localhost:#{bypass.port}/item/2", plug: plug)
      end)

      # Verify cassette has 2 interactions
      cassette_path = Path.join(@cassette_dir, "append.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)

      assert length(cassette["interactions"]) == 2
    end
  end

  describe "mode: :bypass" do
    test "always hits network, never creates cassette" do
      bypass = Bypass.open()

      # Expect multiple calls
      Bypass.expect(bypass, "GET", "/live", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{live: true}))
      end)

      # First call
      result1 =
        with_cassette("bypass_test", [cassette_dir: @cassette_dir, mode: :bypass], fn plug ->
          Req.get!("http://localhost:#{bypass.port}/live", plug: plug)
        end)

      assert result1.body["live"] == true

      # Verify no cassette was created
      cassettes = File.ls!(@cassette_dir)
      assert length(cassettes) == 0

      # Second call - also hits network
      result2 =
        with_cassette("bypass_test", [cassette_dir: @cassette_dir, mode: :bypass], fn plug ->
          Req.get!("http://localhost:#{bypass.port}/live", plug: plug)
        end)

      assert result2.body["live"] == true
    end
  end
end
