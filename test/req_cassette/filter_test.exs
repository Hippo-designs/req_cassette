defmodule ReqCassette.FilterTest do
  use ExUnit.Case, async: true

  import ReqCassette

  alias Plug.Conn

  @cassette_dir "test/fixtures/filter"

  setup do
    File.rm_rf!(@cassette_dir)
    File.mkdir_p!(@cassette_dir)
    :ok
  end

  describe "filter_sensitive_data" do
    test "filters API keys from request body" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/auth", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{status: "ok"}))
      end)

      # Make request with API key
      with_cassette(
        "auth",
        [
          cassette_dir: @cassette_dir,
          filter_sensitive_data: [
            {~r/api_key=[\w-]+/, "api_key=<REDACTED>"}
          ]
        ],
        fn plug ->
          Req.post!(
            "http://localhost:#{bypass.port}/auth?api_key=secret123",
            plug: plug
          )
        end
      )

      # Verify cassette was created and API key is redacted
      cassette_path = Path.join(@cassette_dir, "auth.json")
      {:ok, data} = File.read(cassette_path)

      refute String.contains?(data, "secret123")
      assert String.contains?(data, "api_key=<REDACTED>")
    end

    test "filters tokens from JSON response body" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/login", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{token: "super-secret-token-123"}))
      end)

      # Make request
      with_cassette(
        "login",
        [
          cassette_dir: @cassette_dir,
          filter_sensitive_data: [
            {~r/"token":"[^"]+"/, ~s("token":"<REDACTED>")}
          ]
        ],
        fn plug ->
          Req.get!("http://localhost:#{bypass.port}/login", plug: plug)
        end
      )

      # Verify token is redacted in cassette
      cassette_path = Path.join(@cassette_dir, "login.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)

      refute String.contains?(data, "super-secret-token-123")
      # Check that the token value in the JSON is redacted
      assert get_in(cassette, ["interactions", Access.at(0), "response", "body_json", "token"]) ==
               "<REDACTED>"
    end

    test "applies multiple regex filters" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/api", fn conn ->
        {:ok, body, conn} = Conn.read_body(conn)

        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(
          200,
          Jason.encode!(%{
            request_received: body,
            api_key: "response-key-456",
            token: "response-token-789"
          })
        )
      end)

      # Make request with multiple sensitive values
      with_cassette(
        "multi_filter",
        [
          cassette_dir: @cassette_dir,
          filter_sensitive_data: [
            # Match keys in query string
            {~r/api_key=[\w-]+/, "api_key=<REDACTED>"},
            {~r/token=[\w-]+/, "token=<REDACTED>"},
            # Match values in JSON (both patterns to cover all bases)
            {~r/response-key-456/, "<REDACTED>"},
            {~r/response-token-789/, "<REDACTED>"}
          ]
        ],
        fn plug ->
          Req.post!(
            "http://localhost:#{bypass.port}/api?api_key=request-key-123&token=request-token-456",
            plug: plug
          )
        end
      )

      # Verify both are redacted
      cassette_path = Path.join(@cassette_dir, "multi_filter.json")
      {:ok, data} = File.read(cassette_path)

      # Check query string redaction
      refute String.contains?(data, "request-key-123")
      refute String.contains?(data, "request-token-456")
      assert String.contains?(data, "api_key=<REDACTED>")
      assert String.contains?(data, "token=<REDACTED>")

      # Check response body redaction
      refute String.contains?(data, "response-key-456")
      refute String.contains?(data, "response-token-789")
    end
  end

  describe "filter_request_headers" do
    test "removes specified request headers" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/api", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{data: "ok"}))
      end)

      # Make request with authorization header
      with_cassette(
        "filtered_headers",
        [
          cassette_dir: @cassette_dir,
          filter_request_headers: ["authorization", "x-api-key"]
        ],
        fn plug ->
          Req.get!(
            "http://localhost:#{bypass.port}/api",
            headers: [
              {"authorization", "Bearer secret-token"},
              {"x-api-key", "my-api-key"},
              {"user-agent", "req/0.5.15"}
            ],
            plug: plug
          )
        end
      )

      # Verify headers are removed from cassette
      cassette_path = Path.join(@cassette_dir, "filtered_headers.json")
      {:ok, data} = File.read(cassette_path)

      refute String.contains?(data, "Bearer secret-token")
      refute String.contains?(data, "my-api-key")
      assert String.contains?(data, "user-agent")
    end

    test "header filtering is case-insensitive" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/api", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{data: "ok"}))
      end)

      # Make request with Authorization (capitalized)
      with_cassette(
        "case_insensitive",
        [
          cassette_dir: @cassette_dir,
          filter_request_headers: ["authorization"]
        ],
        fn plug ->
          Req.get!(
            "http://localhost:#{bypass.port}/api",
            headers: [{"Authorization", "Bearer token"}],
            plug: plug
          )
        end
      )

      # Verify header is removed regardless of case
      cassette_path = Path.join(@cassette_dir, "case_insensitive.json")
      {:ok, data} = File.read(cassette_path)

      refute String.contains?(data, "Bearer token")
    end
  end

  describe "filter_response_headers" do
    test "removes specified response headers" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/api", fn conn ->
        conn
        |> Conn.put_resp_header("set-cookie", "session=abc123; HttpOnly")
        |> Conn.put_resp_header("x-secret", "secret-value")
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{data: "ok"}))
      end)

      # Make request
      with_cassette(
        "filtered_response_headers",
        [
          cassette_dir: @cassette_dir,
          filter_response_headers: ["set-cookie", "x-secret"]
        ],
        fn plug ->
          Req.get!("http://localhost:#{bypass.port}/api", plug: plug)
        end
      )

      # Verify response headers are removed
      cassette_path = Path.join(@cassette_dir, "filtered_response_headers.json")
      {:ok, data} = File.read(cassette_path)

      refute String.contains?(data, "session=abc123")
      refute String.contains?(data, "secret-value")
      assert String.contains?(data, "content-type")
    end
  end

  describe "before_record callback" do
    test "applies custom filtering logic" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/users", fn conn ->
        {:ok, body, conn} = Conn.read_body(conn)
        user = Jason.decode!(body)

        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(
          200,
          Jason.encode!(%{
            id: 1,
            email: user["email"],
            password: "hashed-password"
          })
        )
      end)

      # Make request with callback to redact email
      redact_email = fn interaction ->
        interaction
        |> update_in(["request", "body_json", "email"], fn _ -> "redacted@example.com" end)
        |> update_in(["response", "body_json", "email"], fn _ -> "redacted@example.com" end)
        |> update_in(["response", "body_json", "password"], fn _ -> "<REDACTED>" end)
      end

      with_cassette(
        "callback_filter",
        [
          cassette_dir: @cassette_dir,
          before_record: redact_email
        ],
        fn plug ->
          Req.post!(
            "http://localhost:#{bypass.port}/users",
            json: %{email: "alice@example.com", password: "secret123"},
            plug: plug
          )
        end
      )

      # Verify callback was applied
      cassette_path = Path.join(@cassette_dir, "callback_filter.json")
      {:ok, data} = File.read(cassette_path)

      refute String.contains?(data, "alice@example.com")
      assert String.contains?(data, "redacted@example.com")
      refute String.contains?(data, "hashed-password")
      assert String.contains?(data, "<REDACTED>")
    end
  end

  describe "combined filters" do
    test "applies all filter types together" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/complete", fn conn ->
        conn
        |> Conn.put_resp_header("set-cookie", "session=xyz")
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(
          200,
          Jason.encode!(%{
            status: "success",
            api_key: "response-api-key"
          })
        )
      end)

      # Apply all filter types
      with_cassette(
        "combined",
        [
          cassette_dir: @cassette_dir,
          filter_sensitive_data: [
            {~r/api_key=[\w-]+/, "api_key=<REDACTED>"},
            {~r/response-api-key/, "<REDACTED>"}
          ],
          filter_request_headers: ["authorization"],
          filter_response_headers: ["set-cookie"],
          before_record: fn interaction ->
            put_in(interaction, ["response", "body_json", "status"], "filtered")
          end
        ],
        fn plug ->
          Req.post!(
            "http://localhost:#{bypass.port}/complete?api_key=secret",
            headers: [{"authorization", "Bearer token"}],
            plug: plug
          )
        end
      )

      # Verify all filters were applied
      cassette_path = Path.join(@cassette_dir, "combined.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)

      # Regex filter - query string
      refute String.contains?(data, "secret")
      assert String.contains?(data, "api_key=<REDACTED>")

      # Regex filter - response body
      refute String.contains?(data, "response-api-key")

      # Request header filter
      refute String.contains?(data, "Bearer token")

      # Response header filter
      refute String.contains?(data, "session=xyz")

      # Callback
      assert get_in(cassette, ["interactions", Access.at(0), "response", "body_json", "status"]) ==
               "filtered"
    end
  end
end
