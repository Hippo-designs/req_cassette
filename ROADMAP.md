# ReqCassette Roadmap

This document outlines the development roadmap for ReqCassette based on the
[Design Specification](docs/DESIGN_SPEC.md).

## Current Status (v0.1.0)

### ✅ Implemented

- **Plug-based Architecture** - Built on Req.Test and Plug.Conn
- **Basic Record/Replay** - Simple GET/POST request handling
- **MD5-based Cassette Matching** - Hash of method + path + query + body
- **JSON Persistence** - Cassettes stored as `{status, headers, body}` JSON
- **Async-Safe Testing** - Process-isolated, no global mocking
- **E2E Tests with Bypass** - Basic test coverage
- **ReqLLM Integration** - Tested with LLM API calls

### ⚠️ Limitations

- Only implicit `:record` mode
- No `use_cassette/2` macro (manual `:plug` option required)
- Cryptic MD5 hash filenames (e.g., `a1b2c3d4e5f6.json`)
- One cassette per HTTP request (can't group related interactions)
- Limited cassette metadata (missing request details, timestamp)
- No configurable request matching (always matches entire request)
- No data sanitization/filtering capabilities
- Basic error messages

---

## Next Release (v0.2.0) - Core Features

**Goal:** Production-ready VCR library with clean API and essential features

### ✅ In Scope

#### 1. Recording Modes

Implement four recording modes via the `:mode` option:

- **`:replay`** (default for CI) - Replay from cassette, error if cassette
  missing
  ```elixir
  use_cassette "api_call", mode: :replay do
    # Must have cassette, network calls will error
  end
  ```

- **`:record`** - Record or overwrite cassettes (force re-record)
  ```elixir
  use_cassette "api_call", mode: :record do
    # Always hits network, overwrites existing cassette
  end
  ```

- **`:record_missing`** (default for dev/test) - Record only if cassette doesn't
  exist
  ```elixir
  use_cassette "api_call", mode: :record_missing do
    # First run: records, subsequent runs: replays
  end
  ```

- **`:bypass`** - Ignore cassettes entirely, always use network
  ```elixir
  use_cassette "api_call", mode: :bypass do
    # Cassettes disabled, direct network call
  end
  ```

**Implementation:**

- Update `ReqCassette.Plug.call/2` with mode-based dispatch logic
- Add mode validation
- Add comprehensive tests for each mode

**Files:**

- `lib/req_cassette/plug.ex` - Mode handling logic
- `test/req_cassette/modes_test.exs` - Mode-specific tests

---

#### 2. `use_cassette/2` and `with_cassette/3`

Implement two complementary APIs for different use cases: implicit
auto-injection (`use_cassette`) and explicit plug passing (`with_cassette`).

**Before (v0.1):**

```elixir
response = Req.get!(
  "https://api.example.com/users/1",
  plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes"}}
)
```

**After (v0.2) - Two Styles:**

##### Style 1: `use_cassette/2` - Implicit (Macro)

Auto-injects plug into all Req calls within block.

```elixir
use ReqCassette

test "fetches user" do
  use_cassette "github_user" do
    response = Req.get!("https://api.example.com/users/1")
    assert response.status == 200
  end
end
```

**Best for:** Simple tests, less boilerplate, automatic behavior

##### Style 2: `with_cassette/3` - Explicit (Function)

Provides plug as argument to lambda - you control where it's used.

```elixir
test "fetches user" do
  with_cassette "github_user", fn plug ->
    response = Req.get!("https://api.example.com/users/1", plug: plug)
    assert response.status == 200
  end
end
```

**Best for:** Helper functions, explicit control, functional style

##### Comparison

| Feature              | `use_cassette`       | `with_cassette`      |
| -------------------- | -------------------- | -------------------- |
| **Type**             | Macro                | Function             |
| **Plug injection**   | Automatic (implicit) | Manual (explicit)    |
| **Syntax**           | `do ... end` block   | Lambda with plug arg |
| **Boilerplate**      | Less                 | Slightly more        |
| **Helper functions** | Harder               | Easier               |
| **Explicitness**     | Implicit             | Explicit             |
| **Learning curve**   | Lower                | Lower                |

##### When to Use Which?

**Use `use_cassette` when:**

- ✅ Writing simple, focused tests
- ✅ All requests in one test block
- ✅ You prefer less boilerplate

**Use `with_cassette` when:**

- ✅ Passing plug to helper functions
- ✅ You prefer explicit, functional style
- ✅ Building reusable test utilities
- ✅ Need clear visibility of what's recorded

##### Shared Features

Both APIs support the same options:

- **Human-readable cassette names** - `github_user.json` instead of
  `a1b2c3d4.json`
- **Cassette options:** `mode`, `cassette_dir`, `match_requests_on`
- **Filtering:** `filter_sensitive_data`, `filter_request_headers`,
  `filter_response_headers`
- **Callbacks:** `before_record`
- **Async-safe:** Both work with `async: true`

##### Examples

**Basic usage (both styles):**

```elixir
# Implicit style
use_cassette "github_user" do
  Req.get!("https://api.github.com/users/wojtekmach")
end

# Explicit style
with_cassette "github_user", fn plug ->
  Req.get!("https://api.github.com/users/wojtekmach", plug: plug)
end
```

**With helper functions (`with_cassette` shines here):**

```elixir
defmodule MyApp.API do
  def fetch_user(id, opts \\ []) do
    Req.get!("https://api.example.com/users/#{id}", plug: opts[:plug])
  end

  def create_user(data, opts \\ []) do
    Req.post!("https://api.example.com/users", json: data, plug: opts[:plug])
  end
end

# Test with explicit plug passing
test "API helper functions" do
  with_cassette "api_operations", fn plug ->
    user = MyApp.API.fetch_user(1, plug: plug)
    assert user.body["id"] == 1

    new_user = MyApp.API.create_user(%{name: "Bob"}, plug: plug)
    assert new_user.status == 201
  end
end
```

**With options:**

```elixir
# use_cassette with options
use_cassette "api_call",
  mode: :replay,
  match_requests_on: [:method, :uri],
  filter_request_headers: ["authorization"] do
  Req.get!("https://api.example.com/data")
end

# with_cassette with options
with_cassette "api_call",
  mode: :replay,
  match_requests_on: [:method, :uri],
  filter_request_headers: ["authorization"],
  fn plug ->
    Req.get!("https://api.example.com/data", plug: plug)
  end
```

**Nested cassettes (different APIs):**

```elixir
# Only possible with with_cassette (explicit plug control)
test "multiple API services" do
  with_cassette "github", fn github_plug ->
    user = Req.get!("https://api.github.com/users/alice",
      plug: github_plug)

    with_cassette "stripe", fn stripe_plug ->
      charge = Req.post!("https://api.stripe.com/v1/charges",
        json: %{amount: 1000},
        plug: stripe_plug)

      {user, charge}
    end
  end
end
```

**Cassette naming:**

```elixir
# Old (v0.1): cassettes/3a7f2c9d8e1b.json
# New (v0.2): cassettes/github_user_wojtekmach.json

# Both APIs support human-readable names
use_cassette "github_user_wojtekmach" do
  # ...
end

with_cassette "github_user_wojtekmach", fn plug ->
  # ...
end

# Supports subdirectories for organization:
use_cassette "api/users/create" do
  # Creates: cassettes/api/users/create.json
end
```

##### Implementation

**`use_cassette/2` - Macro:**

```elixir
defmodule ReqCassette do
  defmacro __using__(_opts) do
    quote do
      import ReqCassette, only: [use_cassette: 2, with_cassette: 2, with_cassette: 3]
    end
  end

  defmacro use_cassette(name, opts \\ [], do: block) do
    # Store context in process dictionary
    # Transform Req calls in block to inject plug
    # Implementation details TBD
  end
end
```

**`with_cassette/3` - Function:**

```elixir
defmodule ReqCassette do
  @doc """
  Execute code with a cassette, providing the plug explicitly.

  Unlike `use_cassette/2` which auto-injects the plug, `with_cassette/3`
  provides the plug configuration as an argument to your function.

  ## Examples

      with_cassette "my_test", fn plug ->
        Req.get!("https://api.example.com/data", plug: plug)
      end

      # With options
      with_cassette "my_test", mode: :replay, fn plug ->
        Req.get!("https://api.example.com/data", plug: plug)
      end

      # Pass to helper functions
      with_cassette "my_test", fn plug ->
        MyApp.API.fetch_user(1, plug: plug)
      end
  """
  @spec with_cassette(String.t(), keyword(), (plug :: term() -> result)) :: result
        when result: any()
  def with_cassette(name, opts \\ [], fun) when is_function(fun, 1) do
    plug_opts = %{
      cassette_name: name,
      cassette_dir: opts[:cassette_dir] || "test/cassettes",
      mode: opts[:mode] || :record_missing,
      match_requests_on: opts[:match_requests_on] || [:method, :uri, :query, :headers, :body],
      filter_sensitive_data: opts[:filter_sensitive_data] || [],
      filter_request_headers: opts[:filter_request_headers] || [],
      filter_response_headers: opts[:filter_response_headers] || [],
      before_record: opts[:before_record]
    }

    plug = {ReqCassette.Plug, plug_opts}
    fun.(plug)
  end
end
```

**Key differences:**

- `use_cassette` - Macro, auto-injects plug (implementation TBD)
- `with_cassette` - Simple function, passes plug to lambda

**Files:**

- `lib/req_cassette.ex` - Both implementations
- `test/req_cassette/use_cassette_test.exs` - `use_cassette` macro tests
- `test/req_cassette/with_cassette_test.exs` - `with_cassette` function tests

---

#### 3. Enhanced Cassette Format

Update JSON format to include full request metadata, pretty-printing, and
intelligent body type handling.

**Current format (v0.1):**

```json
{
  "status": 200,
  "headers": { "content-type": ["application/json"] },
  "body": "{\"id\":1,\"name\":\"Alice\"}"
}
```

**New format (v0.2) - Pretty-printed with native JSON:**

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
          "content-type": ["application/json"],
          "cache-control": ["max-age=300"]
        },
        "body_type": "json",
        "body_json": {
          "id": 1,
          "name": "Alice",
          "email": "alice@example.com",
          "roles": ["admin", "user"]
        }
      },
      "recorded_at": "2025-10-16T14:23:45.123456Z"
    }
  ]
}
```

**Key improvements:**

##### 3.1 Pretty-Printed JSON

Use `Jason.encode!(cassette, pretty: true)` for human-readable cassettes.

**Before (compact, single-line):**

```json
{
  "version": "1.0",
  "interactions": [
    { "request": { "method": "GET" }, "response": { "status": 200 } }
  ]
}
```

**After (pretty-printed):**

```json
{
  "version": "1.0",
  "interactions": [
    {
      "request": { "method": "GET" },
      "response": { "status": 200 }
    }
  ]
}
```

**Benefits:**

- Human-readable with proper indentation
- Better code review experience
- Easier manual editing
- Clearer git diffs

##### 3.2 Body Type Discrimination

Add `body_type` field with three types: `"json"`, `"text"`, `"blob"`.

**Body type: `json`** - Store as native JSON object (no escaping,
pretty-printed)

**Before (v0.1):**

```json
{
  "response": {
    "body": "{\"token\":\"abc123\",\"user\":{\"id\":1,\"name\":\"Alice\"}}"
  }
}
```

Problem: Double-encoded JSON, escaped quotes, unreadable

**After (v0.2):**

```json
{
  "response": {
    "body_type": "json",
    "body_json": {
      "token": "abc123",
      "user": {
        "id": 1,
        "name": "Alice"
      }
    }
  }
}
```

✅ Native JSON object, no escaping, readable!

**Body type: `blob`** - Store binary data as base64

```json
{
  "response": {
    "status": 200,
    "headers": {
      "content-type": ["image/png"]
    },
    "body_type": "blob",
    "body_blob": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ..."
  }
}
```

Use cases:

- Image downloads (PNG, JPEG, GIF)
- PDF documents
- Compressed data (gzip)
- Binary formats (protobuf, msgpack)

**Body type: `text`** - Store plain text as string

```json
{
  "response": {
    "body_type": "text",
    "body": "<html><body>Success!</body></html>"
  }
}
```

Use cases:

- HTML responses
- XML/SOAP
- Plain text
- CSV files

**Benefits:**

- **Dramatically better readability** - JSON as native objects, not escaped
  strings
- **Better git diffs** - Object property changes vs entire string changes
  ```diff
    "body_json": {
  -   "followers": 100
  +   "followers": 150
    }
  ```
- **Binary support** - Can test image/PDF downloads and binary APIs
- **Smaller files** - Native JSON ~40% smaller than escaped strings
  - Before: `"body": "{\"users\":[{\"id\":1},{\"id\":2}]}"` (106 bytes)
  - After: `"body_json": {"users":[{"id":1},{"id":2}]}` (47 bytes)

**Overall benefits:**

- **Debugging** - See exact request that generated response
- **Auditing** - Know when cassettes were recorded (identify stale data)
- **Logical grouping** - All requests from one test in a single cassette file
- **Better organization** - One file instead of many MD5 hash files
- **Version field** - Enable future format migrations
- **Readability** - Pretty-printed with native JSON objects
- **Binary support** - Handle any content type

**Example workflow cassette:**

```elixir
# Single test with multiple API calls
test "complete user workflow" do
  use_cassette "user_workflow" do
    # Login
    {:ok, auth} = Req.post!("https://api.example.com/auth/login",
      json: %{username: "alice", password: "secret"})

    # Fetch profile
    {:ok, profile} = Req.get!("https://api.example.com/users/me",
      headers: [{"authorization", "Bearer #{auth.body["token"]}"}])

    # Update profile
    {:ok, _} = Req.put!("https://api.example.com/users/me",
      json: %{bio: "New bio"})
  end
end

# All 3 interactions stored in cassettes/user_workflow.json:
# {
#   "version": "1.0",
#   "interactions": [
#     {"request": {POST /auth/login}, "response": {...}},
#     {"request": {GET /users/me}, "response": {...}},
#     {"request": {PUT /users/me}, "response": {...}}
#   ]
# }
```

**Implementation:**

- **Body type detection:**
  - Create `detect_body_type(body, headers)` function
  - Check `content-type` header for type hints
  - Use `String.printable?/1` to detect binary data
  - Try `Jason.decode/1` to detect valid JSON

- **Serialization:**
  - Update `save_cassette/3` to:
    - Detect request and response body types
    - Store as `body_json`, `body_blob`, or `body` accordingly
    - Base64 encode binary data
    - Use `Jason.encode!(cassette, pretty: true)` for final output

- **Deserialization:**
  - Update `maybe_load_cassette/2` to:
    - Read `body_type` field
    - Decode based on type (JSON, base64, or raw string)
    - Handle backward compatibility (v0.1 format without `body_type`)

- **Migration:**
  - Add `mix cassette.migrate` task to convert old cassettes
  - Warn users when loading old format cassettes

**Files:**

- `lib/req_cassette/body_type.ex` - Body type detection and encoding/decoding
- `lib/req_cassette/plug.ex` - Serialization updates (use body types, pretty
  print)
- `lib/req_cassette/cassette.ex` - Cassette schema and validation
- `lib/mix/tasks/cassette.migrate.ex` - Migration task
- `test/req_cassette/body_type_test.exs` - Body type detection tests

---

#### 4. Sensitive Data Filtering

Implement data sanitization to prevent API keys, tokens, and PII from being
committed.

**Features:**

##### Per-Cassette Filtering

```elixir
use_cassette "api_call",
  filter_sensitive_data: [
    # Regex pattern replacement
    {~r/api_key=[\w-]+/, "api_key=<REDACTED>"},
    {~r/"token":"[^"]+"/, "\"token\":\"<REDACTED>\""}
  ],
  filter_request_headers: ["authorization", "x-api-key"],
  filter_response_headers: ["set-cookie"] do
  # Filters applied before saving cassette
end
```

##### Callback-Based Filtering

```elixir
use_cassette "api_call",
  before_record: fn interaction ->
    # Programmatically modify interaction before save
    interaction
    |> update_in(["response", "body"], &redact_email/1)
    |> put_in(["request", "headers", "authorization"], ["<REDACTED>"])
  end do
  # ...
end
```

**Implementation:**

- Add filter application in `save_cassette/3`
- Support regex-based replacements
- Support header removal/redaction
- Support callback functions for complex filtering

**Files:**

- `lib/req_cassette/filter.ex` - Filtering engine
- `lib/req_cassette/plug.ex` - Apply filters before save
- `test/req_cassette/filter_test.exs` - Filter tests

---

#### 5. Request Matching Options

Implement the `:match_requests_on` option for flexible request matching (Design
§5.1).

**Default behavior (match all):**

```elixir
use_cassette "api_call" do
  # Matches on: method + uri + query + headers + body (default)
end
```

**Custom matching:**

```elixir
use_cassette "api_call", match_requests_on: [:method, :uri] do
  # Ignores query params, headers, and body differences
  # Useful when headers contain timestamps or request IDs
end
```

**Available matchers:**

- **`:method`** - HTTP method (GET, POST, etc.)
  ```elixir
  match_requests_on: [:method, :uri]
  ```

- **`:uri`** - Full URI including scheme, host, port, path (excludes query
  string)
  ```elixir
  match_requests_on: [:method, :uri, :query]
  ```

- **`:query`** - Query string parameters (order-insensitive)
  ```elixir
  # Matches: ?a=1&b=2 and ?b=2&a=1 (same parameters, different order)
  match_requests_on: [:method, :uri, :query]
  ```

- **`:headers`** - Request headers (exact match)
  ```elixir
  match_requests_on: [:method, :uri, :headers]
  ```

- **`:body`** - Request body
  ```elixir
  # For JSON bodies: key order doesn't matter
  # {"a":1,"b":2} matches {"b":2,"a":1}
  match_requests_on: [:method, :uri, :body]
  ```

**Common patterns:**

```elixir
# Ignore dynamic headers (timestamps, request IDs, etc.)
use_cassette "api", match_requests_on: [:method, :uri, :body] do
  # Headers ignored - useful for APIs that add x-request-id
end

# Ignore request body (GET/DELETE with cache-busting params)
use_cassette "api", match_requests_on: [:method, :uri, :query] do
  # Body ignored
end

# Match only method and path (most permissive)
use_cassette "api", match_requests_on: [:method, :uri] do
  # Useful during development when request format is changing
end
```

**Implementation:**

- Add matcher modules in `lib/req_cassette/matchers/`
  - `method.ex` - Method comparison
  - `uri.ex` - URI comparison
  - `query.ex` - Query string normalization and comparison
  - `headers.ex` - Header comparison
  - `body.ex` - Body comparison (content-type aware)

- Update `ReqCassette.Plug.call/2` to use matcher pipeline
- Support custom matcher functions (future: v0.3)

**Query string normalization:**

```elixir
# Both match the same cassette interaction:
?filter=active&page=1&limit=10
?page=1&limit=10&filter=active
```

**JSON body normalization:**

```elixir
# Both match the same cassette interaction:
{"user": "alice", "action": "login"}
{"action": "login", "user": "alice"}
```

**Files:**

- `lib/req_cassette/matchers/method.ex`
- `lib/req_cassette/matchers/uri.ex`
- `lib/req_cassette/matchers/query.ex`
- `lib/req_cassette/matchers/headers.ex`
- `lib/req_cassette/matchers/body.ex`
- `lib/req_cassette/matcher.ex` - Matcher pipeline coordinator
- `test/req_cassette/matchers_test.exs` - Individual matcher tests
- `test/req_cassette/matching_test.exs` - Integration tests

---

#### 6. Comprehensive Testing

Expand test coverage to match Design Specification §6.0:

##### Unit Tests

- [ ] Recording mode logic (replay, record, record_missing, bypass)
- [ ] Request matching (method, uri, query, headers, body matchers)
- [ ] Query string normalization (order-insensitive)
- [ ] JSON body normalization (key-order insensitive)
- [ ] **Body type detection** (json, text, blob)
  - [ ] Detect JSON from content-type header
  - [ ] Detect binary data with `String.printable?/1`
  - [ ] Fallback to JSON parsing attempt
  - [ ] Handle already-decoded Req responses
- [ ] **Body encoding/decoding**
  - [ ] JSON bodies stored as native objects
  - [ ] Binary bodies base64 encoded/decoded
  - [ ] Text bodies stored as strings
- [ ] **Pretty-printing** validation
  - [ ] Cassettes saved with `pretty: true`
  - [ ] Output is valid JSON
  - [ ] Proper indentation
- [ ] Cassette matching algorithm with multiple interactions
- [ ] Filter functions (regex, headers, callbacks)
- [ ] Cassette serialization/deserialization (v1.0 format)
- [ ] Backward compatibility with v0.1 cassettes (no `body_type` field)
- [ ] **`use_cassette` macro** functionality
  - [ ] Macro expansion and AST transformation
  - [ ] Process dictionary handling for cassette context
  - [ ] Auto-injection of plug into Req calls
- [ ] **`with_cassette` function** functionality
  - [ ] Options parsing and plug configuration
  - [ ] Lambda execution with plug argument
  - [ ] Return value preservation
- [ ] Filename sanitization for cassette names

##### Integration Tests

- [ ] Plug call with fixture cassettes (no network)
- [ ] Mode behavior with existing/missing cassettes
- [ ] **Both API styles** (`use_cassette` and `with_cassette`)
  - [ ] Same cassette name works with both APIs
  - [ ] Options applied correctly in both APIs
  - [ ] Nested cassettes (only with `with_cassette`)
- [ ] Request matching with different matcher combinations
- [ ] Multiple interactions per cassette file
- [ ] **Body type handling** in cassettes
  - [ ] JSON body saves as native object, loads correctly
  - [ ] Binary body saves as base64, loads correctly
  - [ ] Text body saves as string, loads correctly
- [ ] **Pretty-printed cassettes** are valid and parseable
- [ ] Filter application pipeline
- [ ] **`with_cassette` specific**
  - [ ] Passing plug to helper functions
  - [ ] Return value preservation
  - [ ] Multiple cassettes with different plugs

##### E2E Tests with Bypass

- [ ] All HTTP methods (GET, POST, PUT, PATCH, DELETE)
- [ ] **Request body types**
  - [ ] JSON request body (POST/PUT with `json: %{...}`)
  - [ ] Form-encoded request body
  - [ ] Binary request body
  - [ ] Empty request body
- [ ] **Response body types**
  - [ ] JSON responses (most common)
  - [ ] HTML/XML responses (text)
  - [ ] Binary responses (images, PDFs)
  - [ ] Empty responses (204 No Content)
- [ ] **Mixed content types in single cassette**
  - [ ] First interaction: JSON response
  - [ ] Second interaction: Binary response
  - [ ] Third interaction: Text response
- [ ] Non-2xx status codes (4xx, 5xx errors)
- [ ] Query parameters and headers
- [ ] Multiple interactions per cassette
- [ ] **Pretty-printed cassette validation**
  - [ ] File is human-readable
  - [ ] Can be manually edited
  - [ ] Git diff shows meaningful changes
- [ ] ReqLLM integration (streaming responses)
- [ ] Concurrent async tests (verify process isolation)

**Files:**

- `test/req_cassette/modes_test.exs` - Recording mode tests
- `test/req_cassette/use_cassette_test.exs` - `use_cassette` macro tests
- `test/req_cassette/with_cassette_test.exs` - `with_cassette` function tests
- `test/req_cassette/filter_test.exs` - Filtering tests
- `test/req_cassette/body_type_test.exs` - Body type detection tests
- `test/req_cassette/cassette_format_test.exs` - Format validation and
  pretty-printing
- `test/req_cassette/e2e_test.exs` - End-to-end with various body types

---

#### 6. Documentation Updates

Update all documentation for v0.2 API:

- [ ] **README.md** - Update with both API examples
  - [ ] Show `use_cassette` for simple cases
  - [ ] Show `with_cassette` for helper functions
  - [ ] When to use which section
- [ ] **Module docs** - Complete @moduledoc for all modules
- [ ] **Function docs** - Complete @doc for all public functions
  - [ ] `use_cassette/2` macro documentation
  - [ ] `with_cassette/2` and `with_cassette/3` function documentation
- [ ] **Guides** - Create comprehensive guides:
  - Getting Started Guide (show both APIs)
  - API Styles Guide (use_cassette vs with_cassette)
  - Recording Modes Guide
  - Request Matching Guide
  - Sensitive Data Filtering Guide
  - Cassette Format Guide (body types, pretty-printing)
  - Binary Data Handling Guide
  - Helper Functions Guide (with_cassette examples)
  - Migration Guide (v0.1 → v0.2)
  - ReqLLM Integration Guide (update existing)
- [ ] **Examples** - Add example projects in `examples/` directory
  - [ ] Simple test suite with `use_cassette`
  - [ ] Test utilities with `with_cassette`
  - [ ] Helper function patterns

**Files:**

- `README.md` - Show both API styles
- `lib/req_cassette.ex` - Both APIs with full documentation
- `lib/req_cassette/plug.ex`
- `lib/req_cassette/filter.ex`
- `lib/req_cassette/matcher.ex`
- `lib/req_cassette/body_type.ex`
- `guides/getting_started.md` - Introduction to both APIs
- `guides/api_styles.md` - When to use use_cassette vs with_cassette
- `guides/recording_modes.md`
- `guides/request_matching.md`
- `guides/filtering.md`
- `guides/cassette_format.md` - Body types and pretty-printing
- `guides/binary_data.md` - Handling images, PDFs, etc.
- `guides/helper_functions.md` - Patterns for with_cassette
- `guides/migration_v0.1_to_v0.2.md`

---

### ❌ Out of Scope (Future Versions)

The following features are deferred to future releases:

#### Global Configuration Module (v0.3)

- `ReqCassette.Config.setup/1`
- Global cassette directory
- Global filter rules
- Global callbacks

#### Advanced Request Matching (v0.3)

- Custom matcher functions (beyond built-in matchers)
- Matcher plugins/extensibility

#### Mix Tasks (v0.3)

- `mix cassette.eject` - Delete cassettes
- `mix cassette.check` - Validate cassettes
- `mix cassette.show` - Pretty-print cassette
- `mix cassette.list` - List all cassettes

#### Advanced Features (v0.4+)

- Dynamic response templating (EEx)
- Pluggable serializers (YAML, ETF)
- Request/response streaming support
- Atomic file writes
- Cassette encryption

---

## Release Plan

### v0.2.0 (Target: Q1 2026)

**Breaking Changes:**

- New cassette format (v1.0 schema)
  - Pretty-printed JSON (multi-line instead of single-line)
  - Body types: `body_json`, `body_blob`, `body` (was just `body`)
  - Multiple interactions per cassette (was single response)
- Two new APIs: `use_cassette/2` macro and `with_cassette/3` function
  - Replaces manual `:plug` option from v0.1
  - Choose implicit (`use_cassette`) or explicit (`with_cassette`) style
- Default mode is `:record_missing` (was implicit `:record`)
- Human-readable filenames (was MD5 hash)

**Migration Path:**

1. Run `mix cassette.migrate` to convert v0.1 cassettes to v0.2 format
2. Choose your API style:
   - **Simple tests:** Use `use_cassette/2` macro
   - **Helper functions:** Use `with_cassette/3` function
3. Update tests to use chosen API (or mix both as needed)
4. Set `mode: :record_missing` for development
5. Set `mode: :replay` in CI environment

**Success Criteria:**

- [ ] All 6 core features implemented
  - [ ] Recording modes (replay, record, record_missing, bypass)
  - [ ] Two API styles
    - [ ] `use_cassette/2` macro (implicit, auto-inject)
    - [ ] `with_cassette/3` function (explicit, lambda-based)
    - [ ] Human-readable cassette names for both
  - [ ] Enhanced cassette format
    - [ ] Pretty-printed JSON
    - [ ] Body type discrimination (json/text/blob)
    - [ ] Logical grouping (multiple interactions)
  - [ ] Sensitive data filtering
  - [ ] Request matching options (match_requests_on)
  - [ ] Comprehensive testing
- [ ] Test coverage > 90%
- [ ] All documentation updated
- [ ] Migration guide complete
- [ ] Example projects added

---

## Contributing

We welcome contributions! To contribute to v0.2 features:

1. Check [Issues](https://github.com/lostbean/req_cassette/issues) for open
   tasks
2. Comment on issue to claim it
3. Follow [CONTRIBUTING.md](CONTRIBUTING.md) guidelines
4. Ensure tests pass: `mix test`
5. Submit pull request

Priority areas for v0.2:

- [ ] Recording modes implementation
- [ ] Two API styles
  - [ ] `use_cassette` macro with auto-injection
  - [ ] `with_cassette` function with explicit plug
  - [ ] Human-readable filenames for both
- [ ] Enhanced cassette format
  - [ ] Pretty-printed JSON output
  - [ ] Body type detection (json/text/blob)
  - [ ] Logical grouping (multiple interactions)
- [ ] Request matching (match_requests_on) implementation
- [ ] Sensitive data filtering
- [ ] Binary data support (base64 encoding)
- [ ] Test coverage improvements (both APIs)
- [ ] Documentation writing (show both API styles)

---

## Questions?

Open an issue or discussion on
[GitHub](https://github.com/lostbean/req_cassette/issues).
