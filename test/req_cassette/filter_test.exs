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

  describe "binary body filtering" do
    test "filters blob bodies with regex patterns" do
      bypass = Bypass.open()

      # Create binary data with a "secret" pattern
      binary_data = "Binary data with secret_pattern_12345 embedded inside"

      Bypass.expect_once(bypass, "GET", "/image", fn conn ->
        conn
        |> Conn.put_resp_content_type("image/png")
        |> Conn.resp(200, binary_data)
      end)

      # Record with filter on binary body
      with_cassette(
        "blob_filter",
        [
          cassette_dir: @cassette_dir,
          filter_sensitive_data: [
            {~r/secret_pattern_\d+/, "REDACTED"}
          ]
        ],
        fn plug ->
          Req.get!("http://localhost:#{bypass.port}/image", plug: plug)
        end
      )

      # Verify the blob was decoded, filtered, and re-encoded correctly
      cassette_path = Path.join(@cassette_dir, "blob_filter.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)

      interaction = hd(cassette["interactions"])
      response = interaction["response"]

      # Should be stored as blob
      assert response["body_type"] == "blob"
      assert response["body_blob"]

      # Decode the blob and verify the filter was applied
      decoded_blob = Base.decode64!(response["body_blob"])
      assert decoded_blob =~ "REDACTED"
      refute decoded_blob =~ "secret_pattern_12345"
      # Ensure the rest of the data is intact
      assert decoded_blob =~ "Binary data with"
      assert decoded_blob =~ "embedded inside"
    end
  end

  describe "replay after filtering" do
    test "replay works after filtering request headers" do
      bypass = Bypass.open()

      # Record phase - expect network call
      Bypass.expect(bypass, "GET", "/api", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{data: "ok"}))
      end)

      cassette_opts = [
        cassette_dir: @cassette_dir,
        mode: :record_missing,
        filter_request_headers: ["authorization", "x-api-key"]
      ]

      # First call with auth header - records to cassette
      response1 =
        with_cassette(
          "filtered_replay",
          cassette_opts,
          fn plug ->
            Req.get!(
              "http://localhost:#{bypass.port}/api",
              headers: [{"authorization", "Bearer secret123"}],
              plug: plug
            )
          end
        )

      assert response1.status == 200
      assert response1.body["data"] == "ok"

      # Verify cassette was created without authorization header
      cassette_path = Path.join(@cassette_dir, "filtered_replay.json")
      {:ok, data} = File.read(cassette_path)
      refute String.contains?(data, "authorization")
      refute String.contains?(data, "secret123")

      # Shut down bypass to ensure no network call on replay
      Bypass.down(bypass)

      # Second call with same auth header - should replay from cassette
      response2 =
        with_cassette(
          "filtered_replay",
          cassette_opts,
          fn plug ->
            Req.get!(
              "http://localhost:#{bypass.port}/api",
              headers: [{"authorization", "Bearer secret123"}],
              plug: plug
            )
          end
        )

      # Should get same response from cassette
      assert response2.status == 200
      assert response2.body["data"] == "ok"

      # Third call with strict replay mode - ensures filtering works in CI
      replay_opts = Keyword.put(cassette_opts, :mode, :replay)

      response3 =
        with_cassette(
          "filtered_replay",
          replay_opts,
          fn plug ->
            Req.get!(
              "http://localhost:#{bypass.port}/api",
              headers: [{"authorization", "Bearer secret123"}],
              plug: plug
            )
          end
        )

      # Should get same response from cassette even in strict replay mode
      assert response3.status == 200
      assert response3.body["data"] == "ok"
    end

    test "replay works with regex filters on query params" do
      bypass = Bypass.open()

      # Record phase
      Bypass.expect(bypass, "GET", "/api", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{result: "success"}))
      end)

      cassette_opts = [
        cassette_dir: @cassette_dir,
        mode: :record_missing,
        filter_sensitive_data: [
          {~r/api_key=[\w-]+/, "api_key=<REDACTED>"}
        ]
      ]

      # First call with API key in query string
      response1 =
        with_cassette(
          "regex_replay",
          cassette_opts,
          fn plug ->
            Req.get!(
              "http://localhost:#{bypass.port}/api?api_key=secret123",
              plug: plug
            )
          end
        )

      assert response1.status == 200
      assert response1.body["result"] == "success"

      # Verify cassette was created with redacted API key
      cassette_path = Path.join(@cassette_dir, "regex_replay.json")
      {:ok, data} = File.read(cassette_path)
      refute String.contains?(data, "secret123")
      assert String.contains?(data, "api_key=<REDACTED>")

      # Shut down bypass
      Bypass.down(bypass)

      # Second call with same API key - should replay from cassette
      response2 =
        with_cassette(
          "regex_replay",
          cassette_opts,
          fn plug ->
            Req.get!(
              "http://localhost:#{bypass.port}/api?api_key=secret123",
              plug: plug
            )
          end
        )

      # Should get same response from cassette
      assert response2.status == 200
      assert response2.body["result"] == "success"

      # Third call with strict replay mode - ensures filtering works in CI
      replay_opts = Keyword.put(cassette_opts, :mode, :replay)

      response3 =
        with_cassette(
          "regex_replay",
          replay_opts,
          fn plug ->
            Req.get!(
              "http://localhost:#{bypass.port}/api?api_key=secret123",
              plug: plug
            )
          end
        )

      # Should get same response from cassette even in strict replay mode
      assert response3.status == 200
      assert response3.body["result"] == "success"
    end

    test "replay works with combined filters" do
      bypass = Bypass.open()

      # Record phase
      Bypass.expect(bypass, "POST", "/complete", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{status: "ok"}))
      end)

      cassette_opts = [
        cassette_dir: @cassette_dir,
        mode: :record_missing,
        filter_sensitive_data: [
          {~r/token=[\w-]+/, "token=<REDACTED>"}
        ],
        filter_request_headers: ["authorization", "x-api-key"]
      ]

      # First call with both filters applied
      response1 =
        with_cassette(
          "combined_replay",
          cassette_opts,
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/complete?token=secret456",
              headers: [
                {"authorization", "Bearer xyz"},
                {"x-api-key", "key123"}
              ],
              plug: plug
            )
          end
        )

      assert response1.status == 200

      # Verify cassette was created with filters applied
      cassette_path = Path.join(@cassette_dir, "combined_replay.json")
      {:ok, data} = File.read(cassette_path)
      refute String.contains?(data, "secret456")
      refute String.contains?(data, "Bearer xyz")
      refute String.contains?(data, "key123")

      # Shut down bypass
      Bypass.down(bypass)

      # Second call - should replay from cassette despite having filtered values
      response2 =
        with_cassette(
          "combined_replay",
          cassette_opts,
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/complete?token=secret456",
              headers: [
                {"authorization", "Bearer xyz"},
                {"x-api-key", "key123"}
              ],
              plug: plug
            )
          end
        )

      # Should get same response from cassette
      assert response2.status == 200
      assert response2.body["status"] == "ok"

      # Third call with strict replay mode - ensures filtering works in CI
      replay_opts = Keyword.put(cassette_opts, :mode, :replay)

      response3 =
        with_cassette(
          "combined_replay",
          replay_opts,
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/complete?token=secret456",
              headers: [
                {"authorization", "Bearer xyz"},
                {"x-api-key", "key123"}
              ],
              plug: plug
            )
          end
        )

      # Should get same response from cassette even in strict replay mode
      assert response3.status == 200
      assert response3.body["status"] == "ok"
    end

    test "replay works with regex filters on JSON request body" do
      bypass = Bypass.open()

      # Record phase - server echoes back the request body
      Bypass.expect(bypass, "POST", "/authenticate", fn conn ->
        {:ok, body, conn} = Conn.read_body(conn)
        request_data = Jason.decode!(body)

        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(
          200,
          Jason.encode!(%{
            authenticated: true,
            user: request_data["username"]
          })
        )
      end)

      cassette_opts = [
        cassette_dir: @cassette_dir,
        mode: :record_missing,
        filter_sensitive_data: [
          # Filter password in JSON request body
          {~r/"password":"[^"]+"/, ~s("password":"<REDACTED>")},
          {~r/"api_key":"[^"]+"/, ~s("api_key":"<REDACTED>")}
        ]
      ]

      # First call with sensitive data in request body
      response1 =
        with_cassette(
          "json_body_replay",
          cassette_opts,
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/authenticate",
              json: %{
                username: "alice",
                password: "secret123",
                api_key: "key-xyz-789"
              },
              plug: plug
            )
          end
        )

      assert response1.status == 200
      assert response1.body["authenticated"] == true
      assert response1.body["user"] == "alice"

      # Verify cassette was created with filtered request body
      cassette_path = Path.join(@cassette_dir, "json_body_replay.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)

      refute String.contains?(data, "secret123")
      refute String.contains?(data, "key-xyz-789")

      # Check that values are redacted in the JSON structure
      interaction = hd(cassette["interactions"])
      assert interaction["request"]["body_json"]["password"] == "<REDACTED>"
      assert interaction["request"]["body_json"]["api_key"] == "<REDACTED>"

      # Shut down bypass
      Bypass.down(bypass)

      # Second call with same sensitive data - should replay from cassette
      response2 =
        with_cassette(
          "json_body_replay",
          cassette_opts,
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/authenticate",
              json: %{
                username: "alice",
                password: "secret123",
                api_key: "key-xyz-789"
              },
              plug: plug
            )
          end
        )

      # Should get same response from cassette
      assert response2.status == 200
      assert response2.body["authenticated"] == true
      assert response2.body["user"] == "alice"

      # Third call with strict replay mode
      replay_opts = Keyword.put(cassette_opts, :mode, :replay)

      response3 =
        with_cassette(
          "json_body_replay",
          replay_opts,
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/authenticate",
              json: %{
                username: "alice",
                password: "secret123",
                api_key: "key-xyz-789"
              },
              plug: plug
            )
          end
        )

      # Should get same response even in strict replay mode
      assert response3.status == 200
      assert response3.body["authenticated"] == true
      assert response3.body["user"] == "alice"
    end

    test "replay works with callback filter modifying request body" do
      bypass = Bypass.open()

      # Record phase
      Bypass.expect(bypass, "POST", "/users", fn conn ->
        {:ok, body, conn} = Conn.read_body(conn)
        user = Jason.decode!(body)

        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(
          200,
          Jason.encode!(%{
            id: 1,
            email: user["email"],
            phone: user["phone"]
          })
        )
      end)

      # Callback that redacts email and phone in request body
      redact_pii = fn interaction ->
        interaction
        |> update_in(["request", "body_json", "email"], fn _ -> "redacted@example.com" end)
        |> update_in(["request", "body_json", "phone"], fn _ -> "555-0000" end)
        |> update_in(["response", "body_json", "email"], fn _ -> "redacted@example.com" end)
        |> update_in(["response", "body_json", "phone"], fn _ -> "555-0000" end)
      end

      cassette_opts = [
        cassette_dir: @cassette_dir,
        mode: :record_missing,
        before_record: redact_pii,
        # Only match on method and URI, not body
        # This allows the callback to safely modify request body without breaking replay
        match_requests_on: [:method, :uri]
      ]

      # First call with real PII
      response1 =
        with_cassette(
          "callback_replay",
          cassette_opts,
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/users",
              json: %{
                email: "alice@example.com",
                phone: "555-1234",
                name: "Alice"
              },
              plug: plug
            )
          end
        )

      assert response1.status == 200
      assert response1.body["id"] == 1

      # Verify cassette was created with redacted PII
      cassette_path = Path.join(@cassette_dir, "callback_replay.json")
      {:ok, data} = File.read(cassette_path)
      refute String.contains?(data, "alice@example.com")
      refute String.contains?(data, "555-1234")
      assert String.contains?(data, "redacted@example.com")
      assert String.contains?(data, "555-0000")

      # Shut down bypass
      Bypass.down(bypass)

      # Second call with same PII - should replay from cassette
      response2 =
        with_cassette(
          "callback_replay",
          cassette_opts,
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/users",
              json: %{
                email: "alice@example.com",
                phone: "555-1234",
                name: "Alice"
              },
              plug: plug
            )
          end
        )

      # Should get same response from cassette
      assert response2.status == 200
      assert response2.body["id"] == 1

      # Third call with strict replay mode
      replay_opts = Keyword.put(cassette_opts, :mode, :replay)

      response3 =
        with_cassette(
          "callback_replay",
          replay_opts,
          fn plug ->
            Req.post!(
              "http://localhost:#{bypass.port}/users",
              json: %{
                email: "alice@example.com",
                phone: "555-1234",
                name: "Alice"
              },
              plug: plug
            )
          end
        )

      # Should get same response even in strict replay mode
      assert response3.status == 200
      assert response3.body["id"] == 1
    end

    test "replay works with regex filters on URI path" do
      bypass = Bypass.open()

      # Record phase - dynamic user ID in path
      Bypass.expect(bypass, "GET", "/api/users/user_12345/profile", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(%{user_id: "user_12345", name: "Alice"}))
      end)

      cassette_opts = [
        cassette_dir: @cassette_dir,
        mode: :record_missing,
        filter_sensitive_data: [
          # Filter user IDs in URI path
          {~r/user_\d+/, "user_<ID>"}
        ]
      ]

      # First call with real user ID in path
      response1 =
        with_cassette(
          "uri_path_replay",
          cassette_opts,
          fn plug ->
            Req.get!(
              "http://localhost:#{bypass.port}/api/users/user_12345/profile",
              plug: plug
            )
          end
        )

      assert response1.status == 200
      assert response1.body["name"] == "Alice"

      # Verify cassette was created with filtered URI
      cassette_path = Path.join(@cassette_dir, "uri_path_replay.json")
      {:ok, data} = File.read(cassette_path)
      refute String.contains?(data, "user_12345")
      assert String.contains?(data, "user_<ID>")

      # Shut down bypass
      Bypass.down(bypass)

      # Second call with same user ID - should replay from cassette
      response2 =
        with_cassette(
          "uri_path_replay",
          cassette_opts,
          fn plug ->
            Req.get!(
              "http://localhost:#{bypass.port}/api/users/user_12345/profile",
              plug: plug
            )
          end
        )

      # Should get same response from cassette
      assert response2.status == 200
      assert response2.body["name"] == "Alice"

      # Third call with strict replay mode
      replay_opts = Keyword.put(cassette_opts, :mode, :replay)

      response3 =
        with_cassette(
          "uri_path_replay",
          replay_opts,
          fn plug ->
            Req.get!(
              "http://localhost:#{bypass.port}/api/users/user_12345/profile",
              plug: plug
            )
          end
        )

      # Should get same response even in strict replay mode
      assert response3.status == 200
      assert response3.body["name"] == "Alice"
    end
  end
end
