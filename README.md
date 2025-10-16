# ReqCassette

[![Hex.pm](https://img.shields.io/hexpm/v/req_cassette.svg)](https://hex.pm/packages/req_cassette)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/req_cassette/)
[![GitHub CI](https://github.com/lostbean/req_cassette/workflows/CI/badge.svg)](https://github.com/lostbean/req_cassette/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> **⚠️ Upgrading from v0.1?** See the [Migration Guide](docs/MIGRATION_V0.1_TO_V0.2.md) for breaking changes and upgrade instructions.

A VCR-style record-and-replay library for Elixir's [Req](https://hexdocs.pm/req)
HTTP client. Record HTTP responses to "cassettes" and replay them in tests for
fast, deterministic, offline-capable testing.

Perfect for testing applications that use external APIs, especially LLM APIs
like Anthropic's Claude!

## Features

- 🎬 **Record & Replay** - Capture real HTTP responses and replay them instantly
- ⚡ **Async-Safe** - Works with `async: true` in ExUnit (unlike ExVCR)
- 🔌 **Built on Req.Test** - Uses Req's native testing infrastructure (no global
  mocking)
- 🤖 **ReqLLM Integration** - Perfect for testing LLM applications (save money
  on API calls!)
- 📝 **Human-Readable** - Pretty-printed JSON cassettes with native JSON objects
- 🎯 **Simple API** - Use `with_cassette` for clean, functional testing
- 🔒 **Sensitive Data Filtering** - Built-in support for redacting secrets
- 🎚️ **Multiple Recording Modes** - Flexible control over when to record/replay
- 📦 **Multiple Interactions** - Store many request/response pairs in one cassette

## Quick Start

```elixir
import ReqCassette

test "fetches user data" do
  with_cassette "github_user", fn plug ->
    response = Req.get!("https://api.github.com/users/wojtekmach", plug: plug)
    assert response.status == 200
    assert response.body["login"] == "wojtekmach"
  end
end
```

**First run**: Records to `test/cassettes/github_user.json`
**Subsequent runs**: Replays instantly from cassette (no network!)

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:req, "~> 0.5.15"},
    {:req_cassette, "~> 0.2.0"}
  ]
end
```

## Usage

### Basic Usage with `with_cassette`

```elixir
import ReqCassette

test "API integration" do
  with_cassette "my_api_call", fn plug ->
    response = Req.get!("https://api.example.com/data", plug: plug)
    assert response.status == 200
  end
end
```

### Recording Modes

Control when to record and replay:

```elixir
# :record_missing (default) - Record if cassette doesn't exist, otherwise replay
with_cassette "api_call", [mode: :record_missing], fn plug ->
  Req.get!("https://api.example.com/data", plug: plug)
end

# :replay - Only replay from cassette, error if missing (great for CI)
with_cassette "api_call", [mode: :replay], fn plug ->
  Req.get!("https://api.example.com/data", plug: plug)
end

# :record - Always hit network and overwrite cassette
with_cassette "api_call", [mode: :record], fn plug ->
  Req.get!("https://api.example.com/data", plug: plug)
end

# :bypass - Ignore cassettes entirely, always use network
with_cassette "api_call", [mode: :bypass], fn plug ->
  Req.get!("https://api.example.com/data", plug: plug)
end
```

### Sensitive Data Filtering

Protect API keys, tokens, and sensitive data:

```elixir
with_cassette "auth",
  [
    filter_request_headers: ["authorization", "x-api-key"],
    filter_response_headers: ["set-cookie"],
    filter_sensitive_data: [
      {~r/api_key=[\w-]+/, "api_key=<REDACTED>"},
      {~r/"token":"[^"]+"/, ~s("token":"<REDACTED>")}
    ]
  ],
  fn plug ->
    Req.post!("https://api.example.com/login",
      json: %{username: "user", password: "secret"},
      plug: plug)
  end
```

### Custom Request Matching

Control which requests match which cassette interactions:

```elixir
# Match only on method and URI (ignore headers, query params, body)
with_cassette "flexible",
  [match_requests_on: [:method, :uri]],
  fn plug ->
    Req.post!("https://api.example.com/data",
      json: %{timestamp: DateTime.utc_now()},
      plug: plug)
  end

# Match on method, URI, and query params (but not body)
with_cassette "search",
  [match_requests_on: [:method, :uri, :query]],
  fn plug ->
    Req.get!("https://api.example.com/search?q=elixir", plug: plug)
  end
```

### With Helper Functions

Perfect for passing plug to reusable functions:

```elixir
defmodule MyApp.API do
  def fetch_user(id, opts \\ []) do
    Req.get!("https://api.example.com/users/#{id}", plug: opts[:plug])
  end

  def create_user(data, opts \\ []) do
    Req.post!("https://api.example.com/users", json: data, plug: opts[:plug])
  end
end

test "user operations" do
  with_cassette "user_workflow", fn plug ->
    user = MyApp.API.fetch_user(1, plug: plug)
    assert user.body["id"] == 1

    new_user = MyApp.API.create_user(%{name: "Bob"}, plug: plug)
    assert new_user.status == 201
  end
end
```

## Usage with ReqLLM

Save money on LLM API calls during testing:

```elixir
import ReqCassette

test "LLM generation" do
  with_cassette "claude_recursion", fn plug ->
    {:ok, response} = ReqLLM.generate_text(
      "anthropic:claude-sonnet-4-20250514",
      "Explain recursion in one sentence",
      max_tokens: 100,
      req_http_options: [plug: plug]
    )

    assert response.choices[0].message.content =~ "function calls itself"
  end
end
```

**First run**: Costs money (real API call)
**Subsequent runs**: FREE (replays from cassette)

See [docs/REQ_LLM_INTEGRATION.md](docs/REQ_LLM_INTEGRATION.md) for detailed
ReqLLM integration guide.

## Cassette Format

Cassettes are stored as pretty-printed JSON with native JSON objects:

```json
{
  "version": "1.0",
  "interactions": [
    {
      "request": {
        "method": "GET",
        "uri": "https://api.example.com/users/1",
        "query_string": "",
        "headers": {
          "accept": ["application/json"]
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
      "recorded_at": "2025-10-16T12:00:00Z"
    }
  ]
}
```

### Body Types

ReqCassette automatically detects and handles three body types:

- **`json`** - Stored as native JSON objects (pretty-printed, readable)
- **`text`** - Plain text (HTML, XML, CSV, etc.)
- **`blob`** - Binary data (images, PDFs) stored as base64

## Configuration Options

```elixir
with_cassette "example",
  [
    cassette_dir: "test/cassettes",              # Where to store cassettes
    mode: :record_missing,                        # Recording mode
    match_requests_on: [:method, :uri, :body],   # Request matching criteria
    filter_sensitive_data: [                      # Regex-based redaction
      {~r/api_key=[\w-]+/, "api_key=<REDACTED>"}
    ],
    filter_request_headers: ["authorization"],   # Headers to remove from requests
    filter_response_headers: ["set-cookie"],     # Headers to remove from responses
    before_record: fn interaction ->              # Custom filtering callback
      # Modify interaction before saving
      interaction
    end
  ],
  fn plug ->
    # Your code here
  end
```

## Why ReqCassette over ExVCR?

| Feature                  | ReqCassette                   | ExVCR                    |
| ------------------------ | ----------------------------- | ------------------------ |
| Async-safe               | ✅ Yes                        | ❌ No                    |
| HTTP client              | Req only                      | hackney, finch, etc.     |
| Implementation           | Req.Test + Plug               | :meck (global)           |
| Pretty-printed cassettes | ✅ Yes (native JSON objects)  | ❌ No (escaped strings)  |
| Multiple interactions    | ✅ Yes (one file per test)    | ❌ No (one file per req) |
| Sensitive data filtering | ✅ Built-in                   | ⚠️ Manual                |
| Recording modes          | ✅ 4 modes                    | ⚠️ Limited               |
| Maintenance              | Low                           | High                     |

## Development

### Quick Commands

```bash
# Development workflow
mix precommit  # Format, check, test (run before commit)
mix ci         # CI checks (read-only format check)
```

### Testing

```bash
# Run all tests (82 tests)
mix test

# Run specific test suite
mix test test/req_cassette/with_cassette_test.exs

# Run demos
mix run examples/httpbin_demo.exs
ANTHROPIC_API_KEY=sk-... mix run examples/req_llm_demo.exs
```

## Documentation

- **[Migration Guide](docs/MIGRATION_V0.1_TO_V0.2.md)** - Upgrading from v0.1 to v0.2
- [ROADMAP.md](ROADMAP.md) - Development roadmap and v0.2 features
- [DESIGN_SPEC.md](docs/DESIGN_SPEC.md) - Complete design specification
- [REQ_LLM_INTEGRATION.md](docs/REQ_LLM_INTEGRATION.md) - ReqLLM integration
  guide
- [DEVELOPMENT.md](docs/DEVELOPMENT.md) - Development guide

## Example Test

```elixir
defmodule MyApp.APITest do
  use ExUnit.Case, async: true

  import ReqCassette

  @cassette_dir "test/fixtures/cassettes"

  test "fetches user data" do
    with_cassette "github_user", [cassette_dir: @cassette_dir], fn plug ->
      response = Req.get!("https://api.github.com/users/wojtekmach", plug: plug)

      assert response.status == 200
      assert response.body["login"] == "wojtekmach"
      assert response.body["public_repos"] > 0
    end
  end

  test "handles API errors gracefully" do
    with_cassette "not_found", [cassette_dir: @cassette_dir], fn plug ->
      response = Req.get!("https://api.github.com/users/nonexistent-user-xyz",
        plug: plug,
        retry: false
      )

      assert response.status == 404
    end
  end
end
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please open an issue or PR.

See [ROADMAP.md](ROADMAP.md) for planned features and development priorities.
