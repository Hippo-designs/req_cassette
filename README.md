# ReqCassette

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
- 📝 **Human-Readable** - JSON cassettes you can inspect and edit
- 🎯 **Simple API** - Just add `plug: {ReqCassette.Plug, ...}` to your Req calls

## Quick Start

```elixir
# First call - records to cassette
response = Req.get!(
  "https://api.example.com/users/1",
  plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes", mode: :record}}
)

# Second call - replays from cassette (instant, no network!)
response = Req.get!(
  "https://api.example.com/users/1",
  plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes", mode: :record}}
)
```

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:req, "~> 0.5.15"},
    {:req_cassette, "~> 0.1.0"}  # or github/path
  ]
end
```

## Usage with ReqLLM

Save money on LLM API calls during testing:

```elixir
# First call costs money
{:ok, response} = ReqLLM.generate_text(
  "anthropic:claude-sonnet-4-20250514",
  "Explain recursion",
  max_tokens: 100,
  req_http_options: [
    plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes", mode: :record}}
  ]
)

# Second call is FREE - replays from cassette!
{:ok, response} = ReqLLM.generate_text(
  "anthropic:claude-sonnet-4-20250514",
  "Explain recursion",
  max_tokens: 100,
  req_http_options: [
    plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes", mode: :record}}
  ]
)
```

See [docs/REQ_LLM_INTEGRATION.md](docs/REQ_LLM_INTEGRATION.md) for detailed
ReqLLM integration guide.

## Development

### Quick Commands

```bash
# Development workflow
mix precommit  # Format, check, test (run before commit)
mix ci         # CI checks (read-only format check)
```

### Code Quality

The project uses Elixir formatter and Credo for code quality. The `mix
precommit` command formats code, checks quality with Credo, and runs tests. The
`mix ci` command is designed for CI environments and only checks formatting
without modifying files.

### Testing

```bash
# Run all tests
mix test

# Run specific test suite
mix test test/req_cassette/plug_test.exs

# Run demos
mix run examples/httpbin_demo.exs
ANTHROPIC_API_KEY=sk-... mix run examples/req_llm_demo.exs
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for detailed development guide.

## Documentation

- [SUMMARY.md](docs/SUMMARY.md) - Complete project overview and architecture
- [DEVELOPMENT.md](docs/DEVELOPMENT.md) - Development guide (setup, testing,
  code quality)
- [REQ_LLM_INTEGRATION.md](docs/REQ_LLM_INTEGRATION.md) - ReqLLM integration
  guide
- [Design Specification](docs/DESIGN_SPEC.md) - Full design spec

## Example Test

```elixir
defmodule MyApp.APITest do
  use ExUnit.Case, async: true

  @cassette_dir "test/fixtures/cassettes"

  setup do
    File.mkdir_p!(@cassette_dir)
    :ok
  end

  test "fetches user data" do
    response = Req.get!(
      "https://api.example.com/users/1",
      plug: {ReqCassette.Plug, %{cassette_dir: @cassette_dir, mode: :record}}
    )

    assert response.status == 200
    assert response.body["name"] == "Alice"
  end
end
```

## Why ReqCassette over ExVCR?

| Feature        | ReqCassette     | ExVCR                |
| -------------- | --------------- | -------------------- |
| Async-safe     | ✅ Yes          | ❌ No                |
| HTTP client    | Req only        | hackney, finch, etc. |
| Implementation | Req.Test + Plug | :meck (global)       |
| Maintenance    | Low             | High                 |

## How It Works

1. **Record Mode**: First request → Hits real API → Saves response to JSON file
2. **Replay Mode**: Subsequent requests → Loads from JSON → Returns instantly

The cassette is matched by HTTP method, path, query string, and request body.

## License

[Add your license]

## Contributing

Contributions welcome! Please open an issue or PR.
