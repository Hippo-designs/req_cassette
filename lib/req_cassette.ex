defmodule ReqCassette do
  @moduledoc """
  A VCR-style record-and-replay library for Elixir's [Req](https://hexdocs.pm/req) HTTP client.

  ReqCassette captures HTTP responses to files ("cassettes") and replays them in subsequent
  test runs, making your tests faster, deterministic, and free from network dependencies.

  ## Features

  - 🎬 **Record & Replay** - Capture real HTTP responses and replay them instantly
  - ⚡ **Async-Safe** - Works with `async: true` in ExUnit (unlike ExVCR)
  - 🔌 **Built on Req.Test** - Uses Req's native testing infrastructure (no global mocking)
  - 🤖 **ReqLLM Integration** - Perfect for testing LLM applications
  - 📝 **Human-Readable** - JSON cassettes you can inspect and edit
  - 🎯 **Simple API** - Just add `plug: {ReqCassette.Plug, ...}` to your Req calls

  ## Quick Start

      # First call - records to cassette
      response = Req.get!(
        "https://api.example.com/users/1",
        plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes"}}
      )

      # Second call - replays from cassette (instant, no network!)
      response = Req.get!(
        "https://api.example.com/users/1",
        plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes"}}
      )

  ## Installation

  Add to your `mix.exs`:

      def deps do
        [
          {:req, "~> 0.5.15"},
          {:req_cassette, "~> 0.1.0"}
        ]
      end

  ## Usage with ReqLLM

      {:ok, response} = ReqLLM.generate_text(
        "anthropic:claude-sonnet-4-20250514",
        "Explain recursion",
        max_tokens: 100,
        req_http_options: [
          plug: {ReqCassette.Plug, %{cassette_dir: "test/cassettes"}}
        ]
      )

  First call costs money, subsequent calls are FREE - replayed from cassette!

  ## How It Works

  1. **Record Mode**: First request → Hits real API → Saves response to JSON file
  2. **Replay Mode**: Subsequent requests → Loads from JSON → Returns instantly

  The cassette is matched by HTTP method, path, query string, and request body.

  ## ExUnit Example

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
            plug: {ReqCassette.Plug, %{cassette_dir: @cassette_dir}}
          )

          assert response.status == 200
          assert response.body["name"] == "Alice"
        end
      end

  ## Documentation

  See `ReqCassette.Plug` for detailed configuration options and API reference.

  ## Why ReqCassette over ExVCR?

  | Feature        | ReqCassette     | ExVCR                |
  | -------------- | --------------- | -------------------- |
  | Async-safe     | ✅ Yes          | ❌ No                |
  | HTTP client    | Req only        | hackney, finch, etc. |
  | Implementation | Req.Test + Plug | :meck (global)       |
  | Maintenance    | Low             | High                 |

  ReqCassette uses Req's native plug system instead of global mocking, making it
  process-isolated, async-safe, and compatible with any Req adapter.
  """
end
