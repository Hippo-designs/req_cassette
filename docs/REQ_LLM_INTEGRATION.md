# ReqLLM Integration with ReqCassette

This document explains how to use ReqCassette with ReqLLM to record and replay
LLM API calls, saving time and money during testing and development.

## Why Use ReqCassette with ReqLLM?

1. **Save Money** - LLM API calls cost money. Recording responses means you only
   pay once.
2. **Faster Tests** - Replaying from cassettes is instant vs waiting for API
   responses.
3. **Deterministic Tests** - Same input always gives same output (replayed from
   cassette).
4. **Offline Development** - Work without internet once cassettes are recorded.
5. **No Rate Limits** - Run tests as many times as you want without hitting API
   rate limits.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:req_llm, "~> 1.0.0-rc.7"},
    {:req_cassette, path: "."} # or from hex when published
  ]
end
```

## Basic Usage

### Simple Example

```elixir
model = "anthropic:claude-sonnet-4-20250514"
prompt = "Explain recursion in one sentence"

# First call - records to cassette
{:ok, response1} = ReqLLM.generate_text(
  model,
  prompt,
  max_tokens: 100,
  req_http_options: [
    plug: {ReqCassette.Plug, %{cassette_name: "llm_example", cassette_dir: "test/cassettes", mode: :record_missing}}
  ]
)

# Second call - replays from cassette (FREE!)
{:ok, response2} = ReqLLM.generate_text(
  model,
  prompt,
  max_tokens: 100,
  req_http_options: [
    plug: {ReqCassette.Plug, %{cassette_name: "llm_example", cassette_dir: "test/cassettes", mode: :record_missing}}
  ]
)

# Extract text from both responses
text1 = ReqLLM.Response.text(response1)
text2 = ReqLLM.Response.text(response2)
text1 == text2  # true - same response replayed!
```

### In Tests

```elixir
defmodule MyApp.LLMTest do
  use ExUnit.Case, async: true

  @cassette_dir "test/fixtures/llm_cassettes"

  setup do
    File.mkdir_p!(@cassette_dir)
    :ok
  end

  test "generates code explanation" do
    {:ok, response} = ReqLLM.generate_text(
      "anthropic:claude-sonnet-4-20250514",
      "Explain what Elixir's pipe operator does",
      max_tokens: 150,
      req_http_options: [
        plug: {ReqCassette.Plug, %{cassette_name: "pipe_explanation", cassette_dir: @cassette_dir, mode: :record_missing}}
      ]
    )

    explanation = ReqLLM.Response.text(response)
    assert explanation =~ ~r/pipe/i
    assert explanation =~ ~r/\|>/
  end
end
```

## ⚠️ Critical for Agents: Recording Mode Selection

**If you're testing LLM agents or multi-turn conversations, you MUST use
`:record_missing` mode, not `:record` mode.**

### The Problem with `:record` Mode

The `:record` mode overwrites the cassette file on **each HTTP request**, not
once at the end. For agents making multiple LLM API calls (tool use, multi-turn
conversations, etc.), **only the last API call will be saved**.

```elixir
# ❌ BROKEN - Agent test will fail on replay!
with_cassette "agent_conversation", [mode: :record], fn plug ->
  {:ok, agent} = MyAgent.start_link(plug: plug)

  # Each call overwrites the cassette
  Agent.prompt(agent, "Hello")        # Cassette: [API call 1]
  Agent.prompt(agent, "How are you?") # Cassette: [API call 2] (lost #1!)
  Agent.prompt(agent, "Goodbye")      # Cassette: [API call 3] (lost #1, #2!)
end
# Result: Only the "Goodbye" interaction is saved ❌
# Replay will fail with "No matching interaction found"
```

### The Solution: Use `:record_missing`

```elixir
# ✅ CORRECT - All agent interactions saved
mode = if System.get_env("RECORD_CASSETTES"), do: :record_missing, else: :replay

with_cassette "agent_conversation", [mode: mode], fn plug ->
  {:ok, agent} = MyAgent.start_link(plug: plug)

  Agent.prompt(agent, "Hello")        # Cassette: [call 1]
  Agent.prompt(agent, "How are you?") # Cassette: [call 1, 2]
  Agent.prompt(agent, "Goodbye")      # Cassette: [call 1, 2, 3]
end
# Result: All 3 interactions saved ✅
```

### Recording Mode Quick Reference

| Mode              | Agent Safe? | Behavior                                     |
| ----------------- | ----------- | -------------------------------------------- |
| `:record_missing` | ✅ Yes      | Accumulates all API calls in cassette        |
| `:record`         | ❌ No       | Overwrites on each request - only saves last |
| `:replay`         | ✅ Yes      | Read-only replay (perfect for CI)            |

**Best Practice:** Use environment variables to control recording:

```elixir
setup do
  mode = case System.get_env("CI") do
    "true" -> :replay  # CI always replays
    _ -> if System.get_env("RECORD"), do: :record_missing, else: :replay
  end

  {:ok, cassette_mode: mode}
end

test "agent workflow", %{cassette_mode: mode} do
  with_cassette "agent_test", [mode: mode], fn plug ->
    # Your agent test here
  end
end
```

## How It Works

1. **First Request** (Recording):

   - ReqCassette intercepts the Req request to the LLM API
   - The request is forwarded to the actual API (costs money)
   - The response is saved to a JSON file (the "cassette")
   - The response is returned to your code

2. **Subsequent Requests** (Replay):
   - ReqCassette intercepts the request
   - It matches the request to a recorded cassette
   - The saved response is returned instantly (NO API call)
   - Your code gets the exact same response as before

## Cassette Matching

Cassettes are matched by creating an MD5 hash of:

- HTTP method (e.g., POST)
- URL path (e.g., `/v1/messages`)
- Query string
- **Request body** (the JSON payload containing your prompt)

This ensures that:

- ✅ Different prompts create different cassettes
- ✅ Same prompt replays from the same cassette
- ✅ Different parameters (max_tokens, temperature) create different cassettes

Example:

```elixir
# These create DIFFERENT cassettes (different prompts)
ReqLLM.generate_text(model, "Hello", max_tokens: 50)
ReqLLM.generate_text(model, "Goodbye", max_tokens: 50)

# These create DIFFERENT cassettes (different parameters)
ReqLLM.generate_text(model, "Hello", max_tokens: 50)
ReqLLM.generate_text(model, "Hello", max_tokens: 100)

# These use the SAME cassette (identical request)
ReqLLM.generate_text(model, "Hello", max_tokens: 50)
ReqLLM.generate_text(model, "Hello", max_tokens: 50)
```

## Configuration Options

The plug options are passed directly in your `Req` call:

```elixir
Req.get(url,
  plug: {ReqCassette.Plug, %{
    cassette_name: "my_api_call",    # Human-readable cassette name
    cassette_dir: "test/cassettes",  # Where to store cassettes
    mode: :record_missing            # ✅ Use :record_missing for safety
  }}
)
```

### Modes

**Available modes:**

- `:record_missing` (**recommended**) - Records if cassette doesn't exist,
  replays if it does. Accumulates all interactions safely.
- `:replay` - Only replay from cassette, error if missing (great for CI)
- `:record` - Always hit network and overwrite cassette ⚠️ **Overwrites on each
  request - use only for single-request tests**
- `:bypass` - Ignore cassettes entirely, always use network

## Examples

### Running the Demo

```bash
# With real API (requires ANTHROPIC_API_KEY)
ANTHROPIC_API_KEY=sk-... mix run examples/req_llm_demo.exs

# First run costs money, second run is free!
```

### Running the Tests

```bash
# Test with mocked LLM server (no API key needed)
mix test test/req_cassette/req_llm_test.exs

# Test with real API (requires API key, costs money - skipped by default)
ANTHROPIC_API_KEY=sk-... mix test --include req_llm
```

## Cassette File Format

Cassettes are stored as JSON files:

```json
{
  "status": 200,
  "headers": {
    "content-type": ["application/json"]
  },
  "body": "{\"id\":\"msg_123\",\"content\":[{\"type\":\"text\",\"text\":\"Hello!\"}],...}"
}
```

## Tips

1. **Commit cassettes to git** - They act as fixtures for your tests
2. **Use descriptive prompts** - Makes it easier to identify which cassette is
   which
3. **Delete cassettes to re-record** - When you want fresh responses
4. **Use :none mode in CI** - Ensures tests don't accidentally make API calls

## Gotchas

### Content-Type Header is Critical

The LLM API returns JSON with `content-type: application/json`. This header
**must** be preserved in the cassette, otherwise Req won't decode the JSON body
and you'll get strings instead of maps.

✅ **Good** - Response body is decoded:

```elixir
response.body["content"]  # Works!
```

❌ **Bad** - Missing content-type means body stays as string:

```elixir
response.body["content"]  # Error: binary doesn't support Access protocol
```

The fixed `ReqCassette.Plug` handles this correctly.

## Advanced: Agent with Tool Calling

The livebook includes `MyAgentWithCassettes`, a GenServer-based agent that
supports both tool calling and cassette recording/replay:

```elixir
# Start agent with cassette support
{:ok, agent} = MyAgentWithCassettes.start_link(
  cassette_opts: [
    cassette_name: "my_agent",
    cassette_dir: "agent_cassettes",
    mode: :record_missing  # ✅ Critical for agents!
  ]
)

# First call - records to cassette (costs money)
MyAgentWithCassettes.prompt(agent, "What is 15 * 7?")

# Second call - replays from cassette (FREE!)
MyAgentWithCassettes.prompt(agent, "What is 15 * 7?")
```

The agent:

- Uses non-streaming responses (required for cassettes)
- Supports tool calling (calculator, web search)
- Maintains conversation history
- Records both initial LLM calls and tool follow-ups

## Streaming Support

ReqLLM supports streaming, but cassettes currently only work with non-streaming
responses. For streaming:

```elixir
# This won't work with cassettes
{:ok, stream} = ReqLLM.stream_text(model, prompt)
```

Use regular `generate_text/3` for cassette support. The livebook includes both:

- `MyAgent` - Streaming version (no cassettes)
- `MyAgentWithCassettes` - Non-streaming version (with cassettes)

## Troubleshooting

### "FunctionClauseError: no function clause matching in Access.get/3"

This means the response body is a string instead of a decoded map.

**Cause**: Missing `content-type` header in cassette.

**Fix**: Delete the cassette and re-record with the fixed `ReqCassette.Plug`.

### Tests are slow

Make sure cassettes are being replayed, not re-recorded each time:

```elixir
# Check cassette directory
IO.inspect(File.ls!("test/cassettes"))

# Should show .json files
```

### Different response each time

If the cassette matching isn't working, check that your request parameters are
identical:

```elixir
# These will create DIFFERENT cassettes
ReqLLM.generate_text(model, "Hello", max_tokens: 50)
ReqLLM.generate_text(model, "Hello", max_tokens: 100)  # Different max_tokens!
```

## Next Steps

- See `lib/req_cassette/plug.ex` for the implementation
- See `test/req_cassette/req_llm_test.exs` for test examples
- See `livebooks/req_llm.livemd` for interactive examples with agents

## Contributing

Found a bug? Have an idea? Open an issue or PR!
