defmodule ReqCassette.PlugTest do
  use ExUnit.Case, async: true

  alias Plug.Conn

  @cassette_dir "test/fixtures/cassettes"

  setup do
    # Clean up cassettes before each test
    File.rm_rf!(@cassette_dir)
    File.mkdir_p!(@cassette_dir)
    :ok
  end

  describe "basic recording and replay" do
    test "records a simple GET request" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/users/1", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{id: 1, name: "Alice"}))
      end)

      # Create a Req request that uses our cassette plug
      response =
        Req.get!(
          "http://localhost:#{bypass.port}/users/1",
          plug: {ReqCassette.Plug, %{cassette_dir: @cassette_dir, mode: :record}}
        )

      assert response.status == 200
      assert response.body["id"] == 1
      assert response.body["name"] == "Alice"

      # Verify cassette was created
      cassettes = File.ls!(@cassette_dir)
      assert length(cassettes) == 1
    end

    test "replays from cassette without hitting the network" do
      bypass = Bypass.open()

      # First request - record
      Bypass.expect_once(bypass, "GET", "/users/2", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{id: 2, name: "Bob"}))
      end)

      _first_response =
        Req.get!(
          "http://localhost:#{bypass.port}/users/2",
          plug: {ReqCassette.Plug, %{cassette_dir: @cassette_dir, mode: :record}}
        )

      # Take down the bypass server to ensure we're not hitting the network
      Bypass.down(bypass)

      # Second request - should replay from cassette
      replay_response =
        Req.get!(
          "http://localhost:#{bypass.port}/users/2",
          plug: {ReqCassette.Plug, %{cassette_dir: @cassette_dir, mode: :record}}
        )

      assert replay_response.status == 200
      assert replay_response.body["id"] == 2
      assert replay_response.body["name"] == "Bob"
    end

    test "handles POST requests with body" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/users", fn conn ->
        {:ok, body, conn} = Conn.read_body(conn)
        user = Jason.decode!(body)

        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(
          201,
          Jason.encode!(%{id: 3, name: user["name"], email: user["email"]})
        )
      end)

      response =
        Req.post!(
          "http://localhost:#{bypass.port}/users",
          json: %{name: "Charlie", email: "charlie@example.com"},
          plug: {ReqCassette.Plug, %{cassette_dir: @cassette_dir, mode: :record}}
        )

      assert response.status == 201
      assert response.body["name"] == "Charlie"
    end

    test "different request bodies create different cassettes" do
      bypass = Bypass.open()

      # Set up bypass to handle multiple requests
      Bypass.expect(bypass, "POST", "/api", fn conn ->
        {:ok, body, conn} = Conn.read_body(conn)
        data = Jason.decode!(body)

        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{result: "Response to: #{data["prompt"]}"}))
      end)

      # First request with prompt "Hello"
      _response1 =
        Req.post!(
          "http://localhost:#{bypass.port}/api",
          json: %{prompt: "Hello"},
          plug: {ReqCassette.Plug, %{cassette_dir: @cassette_dir, mode: :record}}
        )

      # Second request with prompt "Goodbye"
      _response2 =
        Req.post!(
          "http://localhost:#{bypass.port}/api",
          json: %{prompt: "Goodbye"},
          plug: {ReqCassette.Plug, %{cassette_dir: @cassette_dir, mode: :record}}
        )

      # Verify two different cassettes were created
      cassettes = File.ls!(@cassette_dir)
      assert length(cassettes) == 2

      # Take down bypass to ensure replay works
      Bypass.down(bypass)

      # Replay both requests and verify they return different responses
      replay1 =
        Req.post!(
          "http://localhost:#{bypass.port}/api",
          json: %{prompt: "Hello"},
          plug: {ReqCassette.Plug, %{cassette_dir: @cassette_dir, mode: :record}}
        )

      replay2 =
        Req.post!(
          "http://localhost:#{bypass.port}/api",
          json: %{prompt: "Goodbye"},
          plug: {ReqCassette.Plug, %{cassette_dir: @cassette_dir, mode: :record}}
        )

      assert replay1.body["result"] == "Response to: Hello"
      assert replay2.body["result"] == "Response to: Goodbye"
    end
  end
end
