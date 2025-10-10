# Simple demo of ReqCassette.Plug
# Run with: mix run examples/simple_demo.exs

# Start Bypass server
{:ok, bypass} = Bypass.open()

# Configure Bypass to return JSON
Bypass.expect_once(bypass, "GET", "/api/users/1", fn conn ->
  conn
  |> Plug.Conn.put_resp_content_type("application/json")
  |> Plug.Conn.resp(200, Jason.encode!(%{id: 1, name: "Alice", role: "admin"}))
end)

IO.puts("Making first request (will record to cassette)...")

# First request - records to cassette
response1 =
  Req.get!(
    "http://localhost:#{bypass.port}/api/users/1",
    plug: {ReqCassette.Plug, %{cassette_dir: "demo_cassettes", mode: :record}}
  )

IO.puts("Response 1 status: #{response1.status}")
IO.puts("Response 1 body: #{inspect(response1.body)}")
IO.puts("")

# Shut down bypass to prove we're not hitting the network
IO.puts("Shutting down Bypass server...")
Bypass.down(bypass)

IO.puts("Making second request (will replay from cassette)...")

# Second request - replays from cassette
response2 =
  Req.get!(
    "http://localhost:#{bypass.port}/api/users/1",
    plug: {ReqCassette.Plug, %{cassette_dir: "demo_cassettes", mode: :record}}
  )

IO.puts("Response 2 status: #{response2.status}")
IO.puts("Response 2 body: #{inspect(response2.body)}")
IO.puts("")

IO.puts("✓ Successfully replayed from cassette without hitting the network!")
IO.puts("Check demo_cassettes/ directory for the recorded cassette file")
