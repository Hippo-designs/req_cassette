# Demo of ReqCassette.Plug using httpbin.org
# Run with: mix run examples/httpbin_demo.exs

cassette_dir = "demo_cassettes"

IO.puts("Making first request to httpbin.org (will record to cassette)...")

# First request - records to cassette
response1 =
  Req.get!(
    "https://httpbin.org/json",
    plug: {ReqCassette.Plug, %{cassette_dir: cassette_dir, mode: :record}}
  )

IO.puts("✓ First request completed")
IO.puts("  Status: #{response1.status}")
IO.puts("  Body preview: #{inspect(Map.take(response1.body, ["slideshow"]))}")
IO.puts("")

IO.puts("Making second request (will replay from cassette - no network call)...")

# Second request - replays from cassette (no network call!)
response2 =
  Req.get!(
    "https://httpbin.org/json",
    plug: {ReqCassette.Plug, %{cassette_dir: cassette_dir, mode: :record}}
  )

IO.puts("✓ Second request completed (from cassette)")
IO.puts("  Status: #{response2.status}")
IO.puts("  Body preview: #{inspect(Map.take(response2.body, ["slideshow"]))}")
IO.puts("")

# Verify both responses are identical
if response1.body == response2.body do
  IO.puts("✓ Responses match! Successfully replayed from cassette.")
else
  IO.puts("✗ Responses don't match")
end

IO.puts("\nCheck #{cassette_dir}/ directory for the recorded cassette file")
