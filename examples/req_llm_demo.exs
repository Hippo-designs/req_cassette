# ReqLLM with ReqCassette Demo
#
# This demonstrates how to use ReqCassette with ReqLLM to:
# 1. Record LLM API responses to cassettes
# 2. Replay from cassettes (no API cost!)
#
# Requirements:
# - Set ANTHROPIC_API_KEY environment variable
#
# Run with:
#   ANTHROPIC_API_KEY=sk-... mix run examples/req_llm_demo.exs
#
# For testing without API key, use the test suite:
#   mix test test/req_cassette/req_llm_test.exs

cassette_dir = "llm_demo_cassettes"
File.mkdir_p!(cassette_dir)

IO.puts("🤖 ReqLLM + ReqCassette Demo\n")

# Check for API key
unless System.get_env("ANTHROPIC_API_KEY") do
  IO.puts("❌ ERROR: ANTHROPIC_API_KEY environment variable not set")
  IO.puts("   Set it with: export ANTHROPIC_API_KEY=sk-...")
  IO.puts("\n   To test without an API key, run the test suite:")
  IO.puts("   mix test test/req_cassette/req_llm_test.exs")
  System.halt(1)
end

model = "anthropic:claude-sonnet-4-20250514"
prompt = "Hello! Please introduce yourself in one sentence."

IO.puts("📝 Making first request to Anthropic API (will record to cassette)...")

{:ok, response1} = ReqLLM.generate_text(
  model,
  prompt,
  max_tokens: 100,
  plug: {ReqCassette.Plug, %{cassette_dir: cassette_dir, mode: :record}}
)

IO.puts("✓ Response: #{response1}\n")

IO.puts("🎬 Making second request (will replay from cassette - NO API CALL!)...")

{:ok, response2} = ReqLLM.generate_text(
  model,
  prompt,
  max_tokens: 100,
  plug: {ReqCassette.Plug, %{cassette_dir: cassette_dir, mode: :record}}
)

IO.puts("✓ Response: #{response2}\n")

if response1 == response2 do
  IO.puts("✅ SUCCESS! Both responses match - replayed from cassette!")
  IO.puts("   💰 Second request cost $0 (no API call made)")
else
  IO.puts("❌ ERROR: Responses don't match")
end

IO.puts("\n📁 Check #{cassette_dir}/ directory for the recorded cassette file")

# Show cassette contents
cassette_files = File.ls!(cassette_dir)
if length(cassette_files) > 0 do
  IO.puts("\n📄 Cassette file preview:")
  cassette_path = Path.join(cassette_dir, List.first(cassette_files))
  {:ok, content} = File.read(cassette_path)
  {:ok, parsed} = Jason.decode(content)

  IO.puts("   Status: #{parsed["status"]}")
  IO.puts("   Headers: #{length(Map.keys(parsed["headers"]))} headers")
  IO.puts("   Body size: #{String.length(parsed["body"])} bytes")
end
