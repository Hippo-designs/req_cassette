# ReqCassette Bug Fixes

## Issues Found and Fixed

### 1. **Missing Request Body in Forwarded Requests**

**Problem:** When recording a new request, the POST/PUT body was not being forwarded to the actual HTTP server.

**Symptom:** POST requests would fail with empty body errors.

**Fix:** Added `Plug.Conn.read_body/1` to read the request body before forwarding:

```elixir
# Read the request body if present
{:ok, body, conn} = Plug.Conn.read_body(conn)

# Add body to request options
req_opts =
  if body != "" do
    req_opts ++ [body: body]
  else
    req_opts
  end
```

**Location:** `lib/req_cassette/plug.ex` - `forward_and_capture/2` function

---

### 2. **Response Body Not Being Decoded**

**Problem:** Response bodies were being returned as JSON strings instead of decoded maps.

**Symptom:** Tests failed with:
```
FunctionClauseError: no function clause matching in Access.get/3
# body was "{\"id\":1}" instead of %{"id" => 1}
```

**Root Cause:** The cassette wasn't storing the `content-type` header, so when Req replayed the response, it didn't know to decode the JSON.

**Fix:** Two parts:
1. Simplified `maybe_load_cassette/2` to keep body as string (let Req decode it based on content-type)
2. Updated test fixtures to include `content-type` header in mock responses

```elixir
# In tests - ensure Bypass sets content-type
conn
|> Plug.Conn.put_resp_content_type("application/json")
|> Plug.Conn.resp(200, Jason.encode!(%{id: 1, name: "Alice"}))
```

**Location:**
- `lib/req_cassette/plug.ex` - `maybe_load_cassette/2` function
- `test/req_cassette/plug_test.exs` - All Bypass.expect blocks

---

### 3. **Improved Scheme Detection**

**Problem:** The scheme (http/https) was being inferred from port number only, which isn't always accurate.

**Fix:** Use `conn.scheme` when available:

```elixir
scheme = to_string(conn.scheme || if(conn.port == 443, do: "https", else: "http"))
```

**Location:** `lib/req_cassette/plug.ex` - `forward_and_capture/2` function

---

## How It Works

1. **Recording:** When a request doesn't have a cassette:
   - Read the request body
   - Forward the full request (method, URL, headers, body) to the real server
   - Save the response (status, headers, body) to a JSON file
   - The body is stored as a string, headers include content-type

2. **Replaying:** When a cassette exists:
   - Load the cassette from disk
   - Return the stored response through Plug.Conn
   - Req sees the content-type header and automatically decodes JSON bodies
   - The decoded body matches what a real request would return

## Testing

Run the tests:
```bash
mix test test/req_cassette/plug_test.exs
```

Run the demo:
```bash
mix run examples/httpbin_demo.exs
```

## Key Insight

**Req's automatic JSON decoding relies on the `content-type` header.** When replaying from cassette, we must:
1. Store the content-type header in the cassette
2. Return the body as a string (not pre-decoded)
3. Let Req's decode_body step handle the parsing

This ensures cassette replay behaves identically to real HTTP requests.
