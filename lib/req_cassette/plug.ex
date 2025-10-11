defmodule ReqCassette.Plug do
  @moduledoc """
  A Plug that intercepts Req HTTP requests and records/replays them from cassette files.

  This module implements the `Plug` behaviour and is designed to be used with Req's
  `:plug` option to enable VCR-style testing for HTTP clients.

  ## Usage

  Pass the plug to Req using the `:plug` option:

      response = Req.get!(
        "https://api.example.com/data",
        plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes"}}
      )

  ## Options

  - `:cassette_dir` - Directory where cassette files are stored (default: `"cassettes"`)
  - `:mode` - Recording mode (currently only `:record` is supported, default: `:record`)

  ## Cassette Matching

  Cassettes are matched by creating an MD5 hash of:

  - HTTP method (e.g., `GET`, `POST`)
  - Request path
  - Query string
  - Request body

  This ensures that different requests create different cassettes, and identical
  requests replay from the same cassette.

  ## Cassette File Format

  Cassettes are stored as JSON files with the following structure:

      {
        "status": 200,
        "headers": {
          "content-type": ["application/json"],
          "cache-control": ["max-age=0"]
        },
        "body": "{\\"key\\":\\"value\\"}"
      }

  The body is stored as a string. When replaying, the `content-type` header tells
  Req how to decode it (e.g., JSON responses are automatically parsed).

  ## Examples

      # Basic usage
      Req.get!(
        "https://api.example.com/users/1",
        plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes"}}
      )

      # POST request with body
      Req.post!(
        "https://api.example.com/users",
        json: %{name: "Alice"},
        plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes"}}
      )

      # With ReqLLM
      ReqLLM.generate_text(
        "anthropic:claude-sonnet-4-20250514",
        "Hello!",
        req_http_options: [
          plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes"}}
        ]
      )

  ## How It Works

  1. **First Request (Recording)**:
     - Intercepts the outgoing request
     - Checks if a matching cassette exists
     - If not found, forwards the request to the real server
     - Saves the response to a cassette file
     - Returns the response

  2. **Subsequent Requests (Replay)**:
     - Intercepts the outgoing request
     - Finds the matching cassette file
     - Loads and returns the saved response
     - No network call is made

  ## Architecture

  This plug uses Req's native testing infrastructure (`Req.Test`), which means:

  - ✅ **Async-safe**: Works with `async: true` in ExUnit
  - ✅ **Process-isolated**: No global state
  - ✅ **Adapter-agnostic**: Works with any Req adapter (Finch, etc.)
  - ✅ **No mocking**: Uses stable, public APIs

  Unlike ExVCR which uses `:meck` for global module patching, ReqCassette
  leverages Req's built-in plug system for clean, isolated testing.
  """
  @behaviour Plug

  import Plug.Conn

  alias Plug.Conn
  alias Req.Steps

  @typedoc """
  Options for configuring the cassette plug.

  - `:cassette_dir` - Directory where cassette files are stored
  - `:mode` - Recording mode (currently only `:record` is supported)
  """
  @type opts :: %{
          cassette_dir: String.t(),
          mode: :record
        }

  @default_opts %{cassette_dir: "cassettes", mode: :record}

  @doc """
  Initializes the plug with the given options.

  Merges the provided options with the default options.

  ## Parameters

  - `opts` - A map of options (see `t:opts/0`)

  ## Returns

  The merged options map.
  """
  @spec init(opts() | map()) :: opts()
  def init(opts) do
    Map.merge(@default_opts, opts)
  end

  @doc """
  Handles an incoming HTTP request by either replaying from cassette or recording.

  This is the main entry point for the plug. It:

  1. Checks if a cassette exists for this request
  2. If yes, loads and replays the response
  3. If no, forwards the request to the real server, records the response, and returns it

  ## Parameters

  - `conn` - The `Plug.Conn` struct representing the incoming request
  - `opts` - The plug options (see `t:opts/0`)

  ## Returns

  A `Plug.Conn` struct with the response set.
  """
  @spec call(Conn.t(), opts()) :: Conn.t()
  def call(conn, opts) do
    # Read the body first so we can include it in the cassette key
    conn = Conn.fetch_query_params(conn)
    {:ok, body, conn} = Conn.read_body(conn)

    key = cassette_key(conn, body, opts)

    case maybe_load_cassette(key, opts) do
      {:ok, %{status: status, headers: headers, body: response_body}} ->
        conn
        |> put_resp_headers(headers)
        |> send_resp(status, serialize_body(response_body))
        |> Conn.halt()

      :not_found ->
        {conn, resp_or_error} = forward_and_capture(conn, body, opts)

        resp =
          case resp_or_error do
            {:ok, %Req.Response{} = r} ->
              r

            %Req.Response{} = r ->
              r

            other ->
              # maybe treat errors differently, or raise
              raise "unexpected response format: #{inspect(other)}"
          end

        save_cassette(key, resp, opts)
        resp_to_conn(conn, resp)
    end
  end

  defp cassette_key(conn, body, _opts) do
    method = conn.method
    path = conn.request_path
    qs = conn.query_string
    # Include body in the hash to ensure different request bodies create different cassettes
    str = "#{method} #{path}?#{qs}#{body}"
    # or :sha256, etc.
    hash = :crypto.hash(:md5, str)
    Base.encode16(hash, case: :lower)
  end

  defp cassette_path(key, opts) do
    dir = opts.cassette_dir
    Path.join(dir, key <> ".json")
  end

  defp save_cassette(key, %Req.Response{status: status, headers: headers, body: body}, opts) do
    path = cassette_path(key, opts)
    File.mkdir_p!(Path.dirname(path))

    body_str =
      cond do
        is_binary(body) ->
          body

        true ->
          Jason.encode!(body)
      end

    map = %{
      "status" => status,
      "headers" => headers,
      "body" => body_str
    }

    File.write!(path, Jason.encode!(map))
  end

  defp maybe_load_cassette(key, opts) do
    path = cassette_path(key, opts)

    if File.exists?(path) do
      with {:ok, data} <- File.read(path),
           {:ok, %{"status" => status, "headers" => hdrs, "body" => body_str}} <-
             Jason.decode(data) do
        # Keep body as string - Req will decode it based on content-type header
        {:ok, %{status: status, headers: hdrs, body: body_str}}
      else
        _ -> :not_found
      end
    else
      :not_found
    end
  end

  defp forward_and_capture(conn, body, _opts) do
    # Convert Plug.Conn to a Req request and run it
    method = conn.method |> String.downcase() |> String.to_atom()
    headers = conn.req_headers

    # Build a full URL from conn
    # Use conn.scheme if available, otherwise infer from port
    scheme = to_string(conn.scheme || if(conn.port == 443, do: "https", else: "http"))
    host = conn.host || "localhost"
    port = conn.port || 80

    full =
      URI.to_string(%URI{
        scheme: scheme,
        host: host,
        port: port,
        path: conn.request_path,
        query: conn.query_string
      })

    # Create request options
    req_opts = [method: method, url: full, headers: headers]

    # Add body if present
    req_opts =
      if body != "" do
        req_opts ++ [body: body]
      else
        req_opts
      end

    # Create a new Req without the plug option to avoid infinite recursion
    req = Req.new(adapter: &Steps.run_finch/1)

    resp = Req.request(req, req_opts)
    {conn, resp}
  end

  defp resp_to_conn(conn, %{status: status, headers: headers, body: body}) do
    conn
    |> put_resp_headers(headers)
    |> send_resp(status, serialize_body(body))
    |> Conn.halt()
  end

  defp serialize_body(body) when is_binary(body), do: body

  defp serialize_body(body) do
    # for map/struct/list — convert to JSON
    Jason.encode!(body)
  end

  defp put_resp_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {k, v_list}, acc ->
      # ensure header name and value are binaries
      value =
        case v_list do
          [v] when is_binary(v) ->
            v

          vs when is_list(vs) ->
            vs
            |> Enum.filter(&is_binary/1)
            |> Enum.join(", ")

          v when is_binary(v) ->
            v

          other ->
            # fallback: convert to string
            to_string(other)
        end

      Conn.put_resp_header(acc, k, value)
    end)
  end
end
