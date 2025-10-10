defmodule ReqCassette.Plug do
  @moduledoc """
  A Plug that intercepts Req HTTP requests and records/replays them from cassette files.
  """
  @behaviour Plug

  import Plug.Conn

  @default_opts %{cassette_dir: "cassettes", mode: :record}

  def init(opts) do
    Map.merge(@default_opts, opts)
  end

  def call(conn, opts) do
    # Read the body first so we can include it in the cassette key
    conn = Plug.Conn.fetch_query_params(conn)
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    key = cassette_key(conn, body, opts)

    case maybe_load_cassette(key, opts) do
      {:ok, %{status: status, headers: headers, body: response_body}} ->
        conn
        |> put_resp_headers(headers)
        |> send_resp(status, serialize_body(response_body))
        |> Plug.Conn.halt()

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
    req = Req.new(adapter: &Req.Steps.run_finch/1)

    resp = Req.request(req, req_opts)
    {conn, resp}
  end

  defp resp_to_conn(conn, %{status: status, headers: headers, body: body}) do
    conn
    |> put_resp_headers(headers)
    |> send_resp(status, serialize_body(body))
    |> Plug.Conn.halt()
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

      Plug.Conn.put_resp_header(acc, k, value)
    end)
  end
end
