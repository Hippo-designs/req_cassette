defmodule ReqCassette.ReqLLMTest do
  use ExUnit.Case, async: true

  alias Plug.Conn
  alias ReqLLM.Response

  @moduletag :req_llm
  @cassette_dir "test/fixtures/llm_cassettes"

  setup do
    # Clean up cassettes before each test
    File.rm_rf!(@cassette_dir)
    File.mkdir_p!(@cassette_dir)

    # Ensure ReqLLM application is started
    Application.ensure_all_started(:req_llm)
    :ok
  end

  describe "ReqLLM integration" do
    @tag :req_llm
    test "records and replays LLM text generation" do
      # This test requires ANTHROPIC_API_KEY environment variable
      # Skip by default to avoid API costs
      # Run with: ANTHROPIC_API_KEY=sk-... mix test --include req_llm

      model = "anthropic:claude-sonnet-4-20250514"
      prompt = "Make a poem about Elixir"

      # Use named cassette so we can switch modes between calls
      cassette_opts_record = %{
        cassette_dir: @cassette_dir,
        cassette_name: "llm_poem_generation",
        mode: :record_missing
      }

      cassette_opts_replay = %{
        cassette_dir: @cassette_dir,
        cassette_name: "llm_poem_generation",
        mode: :replay
      }

      # First request - records to cassette
      {:ok, response1} =
        ReqLLM.generate_text(
          model,
          prompt,
          temperature: 1.0,
          max_tokens: 50,
          req_http_options: [
            plug: {ReqCassette.Plug, cassette_opts_record}
          ]
        )

      assert %Response{} = response1
      text1 = Response.text(response1)
      assert is_binary(text1)
      assert String.length(text1) > 0

      # Verify cassette was created
      cassettes = File.ls!(@cassette_dir)
      assert length(cassettes) == 1

      # Verify cassette interactions after first call
      cassette_path = Path.join(@cassette_dir, "llm_poem_generation.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)
      interactions_count = length(cassette["interactions"])

      # Second request - replays from cassette (guaranteed no API call)
      {:ok, response2} =
        ReqLLM.generate_text(
          model,
          prompt,
          temperature: 1.0,
          max_tokens: 50,
          req_http_options: [
            plug: {ReqCassette.Plug, cassette_opts_replay}
          ]
        )

      # Both responses should be identical (replayed from cassette)
      text2 = Response.text(response2)
      assert text1 == text2
      assert response1.id == response2.id

      # Verify no new cassettes were created (replayed from existing)
      cassettes_after = File.ls!(@cassette_dir)
      assert length(cassettes_after) == 1

      # Verify interaction count unchanged (replay didn't add new interactions)
      {:ok, data_after} = File.read(cassette_path)
      {:ok, cassette_after} = Jason.decode(data_after)
      assert length(cassette_after["interactions"]) == interactions_count
    end

    @tag capture_log: true
    test "works with mocked LLM response" do
      # This test uses Bypass to mock the LLM API, so no real API key needed
      bypass = Bypass.open()

      # Mock Anthropic API response
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        # Read request body to verify it's being sent
        {:ok, body, conn} = Conn.read_body(conn)
        request_data = Jason.decode!(body)

        # Verify the request has the expected structure
        assert request_data["model"] =~ ~r/claude/
        assert is_list(request_data["messages"])

        # Return a mock Anthropic response
        response = %{
          id: "msg_test123",
          type: "message",
          role: "assistant",
          content: [
            %{
              type: "text",
              text: "Hello from cassette test"
            }
          ],
          model: "claude-sonnet-4-20250514",
          stop_reason: "end_turn",
          usage: %{
            input_tokens: 10,
            output_tokens: 5
          }
        }

        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, Jason.encode!(response))
      end)

      # Make the request through our cassette plug
      # Use named cassette so we can switch modes between calls
      cassette_opts_record = %{
        cassette_dir: @cassette_dir,
        cassette_name: "mocked_llm_response",
        mode: :record_missing
      }

      cassette_opts_replay = %{
        cassette_dir: @cassette_dir,
        cassette_name: "mocked_llm_response",
        mode: :replay
      }

      messages = "Say hello"

      result =
        Req.post!(
          "http://localhost:#{bypass.port}/v1/messages",
          json: %{
            model: "claude-sonnet-4-20250514",
            messages: [%{role: "user", content: messages}],
            max_tokens: 50
          },
          plug: {ReqCassette.Plug, cassette_opts_record}
        )

      assert result.status == 200
      assert result.body["content"]

      assert result.body["content"] |> List.first() |> Map.get("text") ==
               "Hello from cassette test"

      # Verify cassette was created
      cassettes_before = File.ls!(@cassette_dir)
      assert length(cassettes_before) == 1

      # Verify cassette interactions after first call
      cassette_path = Path.join(@cassette_dir, "mocked_llm_response.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)
      interactions_count = length(cassette["interactions"])

      # Shut down bypass to ensure replay doesn't hit network
      Bypass.down(bypass)

      # Replay from cassette (guaranteed no network hit)
      replay_result =
        Req.post!(
          "http://localhost:#{bypass.port}/v1/messages",
          json: %{
            model: "claude-sonnet-4-20250514",
            messages: [%{role: "user", content: messages}],
            max_tokens: 50
          },
          plug: {ReqCassette.Plug, cassette_opts_replay}
        )

      # Should get same response from cassette
      assert replay_result.status == 200
      assert replay_result.body == result.body

      # Verify no new cassettes were created (replayed from existing)
      cassettes_after = File.ls!(@cassette_dir)
      assert length(cassettes_after) == 1

      # Verify interaction count unchanged (replay didn't add new interactions)
      {:ok, data_after} = File.read(cassette_path)
      {:ok, cassette_after} = Jason.decode(data_after)
      assert length(cassette_after["interactions"]) == interactions_count
    end
  end
end
