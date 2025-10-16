defmodule ReqCassette.Cassette do
  @moduledoc """
  Handles cassette file format v1.0 with multiple interactions per file.

  This module provides the core functionality for creating, loading, saving, and searching
  cassette files. Cassettes store HTTP request/response pairs ("interactions") in a
  human-readable JSON format.

  ## Cassette Format v1.0

  Each cassette file contains a version field and an array of interactions:

  ```json
  {
    "version": "1.0",
    "interactions": [
      {
        "request": {
          "method": "GET",
          "uri": "https://api.example.com/users/1",
          "query_string": "filter=active",
          "headers": {
            "accept": ["application/json"],
            "user-agent": ["req/0.5.15"]
          },
          "body_type": "text",
          "body": ""
        },
        "response": {
          "status": 200,
          "headers": {
            "content-type": ["application/json"]
          },
          "body_type": "json",
          "body_json": {
            "id": 1,
            "name": "Alice"
          }
        },
        "recorded_at": "2025-10-16T14:23:45.123456Z"
      }
    ]
  }
  ```

  ## Key Features

  ### Multiple Interactions Per Cassette

  Multiple interactions can be stored in a single cassette file with human-readable names:

      # All requests in one test go to one cassette
      ReqCassette.with_cassette("user_workflow", [], fn plug ->
        user = Req.get!("/users/1", plug: plug)      # Interaction 1
        posts = Req.get!("/posts", plug: plug)       # Interaction 2
        comments = Req.get!("/comments", plug: plug) # Interaction 3
      end)
      # Creates: user_workflow.json with 3 interactions

  Benefits:
  - Related requests grouped together
  - Meaningful filenames
  - Logical workflow organization

  ### Body Type Discrimination

  Bodies are stored in one of three formats based on content type:

  - `body_json` - JSON responses stored as native Elixir data structures
  - `body` - Text responses (HTML, XML, CSV) stored as strings
  - `body_blob` - Binary data (images, PDFs) base64-encoded

  Example JSON storage:
  ```json
  "body_json": {
    "id": 1,
    "name": "Alice"
  }
  ```

  Benefits:
  - Compact cassette files
  - No double-encoding/escaping
  - Human-readable JSON responses
  - Easy to edit or debug

  ### Pretty-Printed JSON

  All cassettes are saved with `Jason.encode!(cassette, pretty: true)` for:

  - Git-friendly diffs
  - Easy manual inspection
  - Debuggability
  - Version control readability

  ### Request Matching with Normalization

  Requests are matched using configurable criteria with automatic normalization:

  - Query parameters are order-independent: `?a=1&b=2` matches `?b=2&a=1`
  - JSON body keys are order-independent: `{"a":1,"b":2}` matches `{"b":2,"a":1}`
  - Headers are case-insensitive: `Accept` matches `accept`

  ## Examples

      # Create a new cassette
      cassette = ReqCassette.Cassette.new()
      #=> %{"version" => "1.0", "interactions" => []}

      # Add an interaction
      cassette = add_interaction(cassette, conn, request_body, response)

      # Save to disk (pretty-printed)
      save("test/cassettes/my_api.json", cassette)

      # Load from disk
      {:ok, cassette} = load("test/cassettes/my_api.json")

      # Find a matching interaction
      case find_interaction(cassette, conn, body, [:method, :uri]) do
        {:ok, response} -> response
        :not_found -> # Record new interaction
      end

      # Multiple interactions in one cassette
      cassette = new()
      cassette = add_interaction(cassette, conn1, body1, resp1)
      cassette = add_interaction(cassette, conn2, body2, resp2)
      cassette = add_interaction(cassette, conn3, body3, resp3)
      save("workflow.json", cassette)
      # workflow.json now contains 3 interactions

  ## See Also

  - `ReqCassette.BodyType` - Body type detection and encoding
  - `ReqCassette.Filter` - Sensitive data filtering
  - `ReqCassette.Plug` - Main plug that uses this module
  """

  alias ReqCassette.BodyType

  @version "1.0"

  @typedoc "A cassette file containing multiple interactions"
  @type t :: %{
          version: String.t(),
          interactions: [interaction()]
        }

  @typedoc "A single HTTP request/response interaction"
  @type interaction :: %{
          request: request(),
          response: response(),
          recorded_at: String.t()
        }

  @typedoc "HTTP request details"
  @type request :: %{
          method: String.t(),
          uri: String.t(),
          query_string: String.t(),
          headers: map(),
          body_type: String.t()
        }

  @typedoc "HTTP response details"
  @type response :: %{
          status: integer(),
          headers: map(),
          body_type: String.t()
        }

  @doc """
  Creates a new empty cassette with version 1.0.

  ## Examples

      new()
      # => %{version: "1.0", interactions: []}
  """
  @spec new() :: map()
  def new do
    %{
      "version" => @version,
      "interactions" => []
    }
  end

  @doc """
  Adds an interaction to a cassette.

  Creates a new interaction from the given request and response, applies any configured
  filters, and appends it to the cassette's interactions array.

  ## Parameters

  - `cassette` - The cassette map (from `new/0` or `load/1`)
  - `conn` - The `Plug.Conn` struct with request details (method, URI, headers, etc.)
  - `request_body` - The raw request body as a binary string
  - `response` - The `Req.Response` struct from the HTTP call
  - `opts` - Optional map of filter options (default: `%{}`)

  ## Filter Options

  The `opts` parameter can include:

  - `:filter_sensitive_data` - List of `{regex, replacement}` tuples
  - `:filter_request_headers` - List of header names to remove from requests
  - `:filter_response_headers` - List of header names to remove from responses
  - `:before_record` - Callback function `(interaction -> interaction)`

  See `ReqCassette.Filter` for details on filtering.

  ## Returns

  Updated cassette map with the new interaction appended to the `"interactions"` array.

  ## Body Type Detection

  This function automatically detects the body type for both request and response:

  - JSON bodies are stored in `body_json` field as native Elixir data structures
  - Text bodies (HTML, XML, CSV) are stored in `body` field as strings
  - Binary bodies (images, PDFs) are base64-encoded in `body_blob` field

  ## Timestamp

  Each interaction includes a `recorded_at` field with an ISO8601 UTC timestamp
  indicating when the interaction was captured.

  ## Examples

      # Basic usage
      cassette = new()
      cassette = add_interaction(cassette, conn, "", response)

      # With filtering
      opts = %{
        filter_sensitive_data: [
          {~r/api_key=[\\w-]+/, "api_key=<REDACTED>"}
        ],
        filter_request_headers: ["authorization"]
      }
      cassette = add_interaction(cassette, conn, body, response, opts)

      # Multiple interactions
      cassette = new()
      cassette = add_interaction(cassette, conn1, body1, resp1)
      cassette = add_interaction(cassette, conn2, body2, resp2)
      cassette = add_interaction(cassette, conn3, body3, resp3)
      # cassette now has 3 interactions

      # With callback filter
      opts = %{
        before_record: fn interaction ->
          put_in(interaction, ["response", "body_json", "secret"], "<REDACTED>")
        end
      }
      cassette = add_interaction(cassette, conn, body, response, opts)
  """
  @spec add_interaction(map(), Plug.Conn.t(), binary(), Req.Response.t(), map()) :: map()
  def add_interaction(cassette, conn, request_body, response, opts \\ %{}) do
    interaction = build_interaction(conn, request_body, response)

    # Apply filters before adding to cassette
    filtered_interaction = ReqCassette.Filter.apply_filters(interaction, opts)

    Map.update!(cassette, "interactions", fn interactions ->
      interactions ++ [filtered_interaction]
    end)
  end

  @doc """
  Finds a matching interaction in the cassette based on request matching criteria.

  Searches through all interactions in the cassette to find one where the request
  matches the given `conn` and `body` according to the specified matchers. Returns
  the first matching interaction's response.

  ## Parameters

  - `cassette` - The cassette map (loaded from `load/1` or created with `new/0`)
  - `conn` - The `Plug.Conn` struct representing the current request
  - `request_body` - The raw request body as a binary string
  - `match_on` - List of matchers that determine matching criteria

  ## Matchers

  The `match_on` parameter accepts a list of atoms that specify what to match:

  - `:method` - HTTP method (GET, POST, etc.) - case-insensitive
  - `:uri` - Full URI including scheme, host, port, and path
  - `:query` - Query parameters - order-independent
  - `:headers` - Request headers - case-insensitive, order-independent
  - `:body` - Request body - JSON bodies are order-independent

  **Common matching strategies:**

  - `[:method, :uri]` - Match only method and path (ignore query, headers, body)
  - `[:method, :uri, :query]` - Match method, path, and query params
  - `[:method, :uri, :query, :body]` - Match method, path, query, and body
  - `[:method, :uri, :query, :headers, :body]` - Match everything (most strict)

  ## Returns

  - `{:ok, response}` - Found a matching interaction, returns the response map
  - `:not_found` - No interaction matches the given criteria

  ## Normalization

  To ensure consistent matching, certain fields are normalized:

  - **Query strings**: `?a=1&b=2` matches `?b=2&a=1`
  - **JSON bodies**: `{"a":1,"b":2}` matches `{"b":2,"a":1}`
  - **Headers**: Case-insensitive comparison, sorted by key

  This allows for flexible matching while maintaining deterministic behavior.

  ## Examples

      # Basic matching on method and URI only
      case find_interaction(cassette, conn, body, [:method, :uri]) do
        {:ok, response} ->
          # Found: use the cached response
          response
        :not_found ->
          # Not found: need to record new interaction
          make_real_request(conn, body)
      end

      # Match on method, URI, and query (useful for GET requests with params)
      find_interaction(cassette, conn, "", [:method, :uri, :query])
      #=> {:ok, %{"status" => 200, "headers" => %{}, ...}}

      # Strict matching (all criteria)
      find_interaction(cassette, conn, body, [:method, :uri, :query, :headers, :body])
      #=> :not_found

      # Ignore request body differences (useful for POST with timestamps)
      conn = %Plug.Conn{method: "POST", request_path: "/api/users", ...}
      body1 = ~s({"name":"Alice","timestamp":"2025-10-16T10:00:00Z"})
      body2 = ~s({"name":"Alice","timestamp":"2025-10-16T10:00:01Z"})

      # First call records with body1
      cassette = add_interaction(cassette, conn, body1, response1)

      # Second call with different body but same method/URI matches!
      find_interaction(cassette, conn, body2, [:method, :uri])
      #=> {:ok, response1}

      # Multiple interactions in cassette - finds first match
      cassette = new()
      |> add_interaction(conn_get, "", resp_get)
      |> add_interaction(conn_post, post_body, resp_post)

      find_interaction(cassette, conn_get, "", [:method, :uri])
      #=> {:ok, resp_get}

      find_interaction(cassette, conn_post, post_body, [:method, :uri, :body])
      #=> {:ok, resp_post}
  """
  @spec find_interaction(map(), Plug.Conn.t(), binary(), [atom()]) ::
          {:ok, map()} | :not_found
  def find_interaction(cassette, conn, request_body, match_on) do
    interactions = Map.get(cassette, "interactions", [])

    Enum.find_value(interactions, :not_found, fn interaction ->
      if interaction_matches?(interaction, conn, request_body, match_on) do
        {:ok, interaction["response"]}
      end
    end)
  end

  @doc """
  Saves a cassette to disk as pretty-printed JSON.

  ## Parameters

  - `path` - File path where cassette should be saved
  - `cassette` - The cassette map

  ## Examples

      save("/path/to/cassette.json", cassette)
  """
  @spec save(String.t(), map()) :: :ok
  def save(path, cassette) do
    File.mkdir_p!(Path.dirname(path))
    json = Jason.encode!(cassette, pretty: true)
    File.write!(path, json)
  end

  @doc """
  Loads a cassette from disk.

  Supports both v1.0 and v0.1 formats for backward compatibility.

  ## Parameters

  - `path` - File path to load cassette from

  ## Returns

  - `{:ok, cassette}` - Successfully loaded cassette (migrated to v1.0 if needed)
  - `:not_found` - File doesn't exist or can't be parsed

  ## Examples

      load("/path/to/cassette.json")
      # => {:ok, %{"version" => "1.0", "interactions" => [...]}}

      load("/path/to/missing.json")
      # => :not_found
  """
  @spec load(String.t()) :: {:ok, map()} | :not_found
  def load(path) do
    if File.exists?(path) do
      with {:ok, data} <- File.read(path),
           {:ok, parsed} <- Jason.decode(data) do
        cassette = migrate_if_needed(parsed)
        {:ok, cassette}
      else
        _ -> :not_found
      end
    else
      :not_found
    end
  end

  # Private helpers

  defp build_interaction(conn, request_body, response) do
    req_body_type = BodyType.detect_type(request_body, conn.req_headers |> headers_to_map())
    {req_body_field, req_body_value} = BodyType.encode(request_body, req_body_type)

    resp_body_type = BodyType.detect_type(response.body, response.headers)
    {resp_body_field, resp_body_value} = BodyType.encode(response.body, resp_body_type)

    %{
      "request" => %{
        "method" => conn.method,
        "uri" => build_uri(conn),
        "query_string" => conn.query_string,
        "headers" => conn.req_headers |> headers_to_map(),
        "body_type" => to_string(req_body_type),
        req_body_field => req_body_value
      },
      "response" => %{
        "status" => response.status,
        "headers" => response.headers,
        "body_type" => to_string(resp_body_type),
        resp_body_field => resp_body_value
      },
      "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_uri(conn) do
    scheme = to_string(conn.scheme || if(conn.port == 443, do: "https", else: "http"))
    host = conn.host || "localhost"
    port = conn.port || 80

    # Only include port if non-standard
    port_str =
      cond do
        scheme == "http" and port == 80 -> ""
        scheme == "https" and port == 443 -> ""
        true -> ":#{port}"
      end

    "#{scheme}://#{host}#{port_str}#{conn.request_path}"
  end

  defp headers_to_map(headers) when is_list(headers) do
    Enum.into(headers, %{}, fn
      {k, v} when is_list(v) -> {k, v}
      {k, v} -> {k, [v]}
    end)
  end

  defp interaction_matches?(interaction, conn, request_body, match_on) do
    request = interaction["request"]

    Enum.all?(match_on, fn matcher ->
      case matcher do
        :method ->
          String.upcase(request["method"]) == String.upcase(conn.method)

        :uri ->
          request["uri"] == build_uri(conn)

        :query ->
          normalize_query(request["query_string"]) == normalize_query(conn.query_string)

        :headers ->
          normalize_headers(request["headers"]) == normalize_headers(conn.req_headers)

        :body ->
          # For JSON bodies, compare normalized JSON
          # For other bodies, compare as strings
          bodies_match?(request, request_body, conn.req_headers)

        _ ->
          true
      end
    end)
  end

  defp bodies_match?(request, conn_body, conn_headers) do
    stored_body = reconstruct_request_body(request)
    stored_type = BodyType.detect_type(stored_body, request["headers"])
    conn_type = BodyType.detect_type(conn_body, headers_to_map(conn_headers))

    cond do
      stored_type == :json and conn_type == :json ->
        # Normalize JSON for comparison (key order doesn't matter)
        normalize_json(stored_body) == normalize_json(conn_body)

      true ->
        # String comparison
        stored_body == conn_body
    end
  end

  defp reconstruct_request_body(request) do
    cond do
      Map.has_key?(request, "body_json") ->
        Jason.encode!(request["body_json"])

      Map.has_key?(request, "body_blob") ->
        Base.decode64!(request["body_blob"])

      Map.has_key?(request, "body") ->
        request["body"]

      true ->
        ""
    end
  end

  defp normalize_query(""), do: %{}

  defp normalize_query(query_string) do
    query_string
    |> URI.decode_query()
    |> Enum.sort()
    |> Enum.into(%{})
  end

  defp normalize_headers(headers) when is_list(headers) do
    headers
    |> headers_to_map()
    |> normalize_headers()
  end

  defp normalize_headers(headers) when is_map(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(k), normalize_header_value(v)} end)
    |> Enum.sort()
    |> Enum.into(%{})
  end

  defp normalize_header_value(v) when is_list(v), do: Enum.sort(v)
  defp normalize_header_value(v), do: [v]

  defp normalize_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> normalize_json(decoded)
      {:error, _} -> body
    end
  end

  defp normalize_json(body) when is_map(body) do
    body
    |> Enum.sort()
    |> Enum.into(%{}, fn {k, v} -> {k, normalize_json(v)} end)
  end

  defp normalize_json(body) when is_list(body) do
    Enum.map(body, &normalize_json/1)
  end

  defp normalize_json(body), do: body

  # Migrate v0.1 cassettes to v1.0 format
  defp migrate_if_needed(%{"version" => "1.0"} = cassette), do: cassette

  defp migrate_if_needed(%{"status" => status, "headers" => headers, "body" => body}) do
    # v0.1 format - single response
    # Convert to v1.0 with one interaction
    # Note: We lose request details in v0.1 migration
    body_type = BodyType.detect_type(body, headers)
    {body_field, body_value} = BodyType.encode(body, body_type)

    %{
      "version" => @version,
      "interactions" => [
        %{
          "request" => %{
            "method" => "UNKNOWN",
            "uri" => "UNKNOWN",
            "query_string" => "",
            "headers" => %{},
            "body_type" => "text",
            "body" => ""
          },
          "response" => %{
            "status" => status,
            "headers" => headers,
            "body_type" => to_string(body_type),
            body_field => body_value
          },
          "recorded_at" => "MIGRATED_FROM_V0.1"
        }
      ]
    }
  end

  defp migrate_if_needed(cassette), do: cassette
end
