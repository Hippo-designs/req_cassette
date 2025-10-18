defmodule ReqCassette.AgentReplayTest do
  use ExUnit.Case, async: false
  require Logger

  @moduletag :req_llm
  @cassette_dir "test/fixtures/agent_cassettes"

  setup do
    # Clean up cassettes before each test
    File.rm_rf!(@cassette_dir)
    File.mkdir_p!(@cassette_dir)

    # Ensure ReqLLM application is started
    Application.ensure_all_started(:req_llm)

    :ok
  end

  defmodule MyAgentWithCassettes do
    @moduledoc """
    A GenServer-based AI agent that supports ReqCassette for recording and replaying LLM calls.
    """
    use GenServer

    alias ReqLLM.{Context, Tool, Response, Message, ToolCall}

    defstruct [:history, :tools, :model, :req_http_options]

    @default_model "anthropic:claude-sonnet-4-20250514"

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def prompt(pid, message) when is_binary(message) do
      GenServer.call(pid, {:prompt, message}, 30_000)
    end

    @impl true
    def init(opts) do
      system_prompt =
        Keyword.get(opts, :system_prompt, """
        You are a helpful AI assistant with access to tools.

        When you need to compute math, use the calculator tool with the expression parameter.

        Do not wrap arguments in code fences. Do not include extra text in arguments.

        When you need to search for information, use the web_search tool with a relevant query.

        Always use tools when appropriate and provide clear, helpful responses.
        """)

      model = Keyword.get(opts, :model, @default_model)
      tools = setup_tools()

      # Setup cassette configuration
      req_http_options =
        case Keyword.get(opts, :cassette_opts) do
          nil ->
            []

          cassette_opts ->
            [plug: {ReqCassette.Plug, Map.new(cassette_opts)}]
        end

      history = Context.new([Context.system(system_prompt)])

      {:ok,
       %__MODULE__{
         history: history,
         tools: tools,
         model: model,
         req_http_options: req_http_options
       }}
    end

    @impl true
    def handle_call({:prompt, message}, _from, state) do
      new_history = Context.append(state.history, Context.user(message))

      case generate_with_tools(state.model, new_history, state.tools, state.req_http_options) do
        {:ok, final_history, final_response} ->
          {:reply, {:ok, final_response}, %{state | history: final_history}}

        {:error, error} ->
          {:reply, {:error, error}, state}
      end
    end

    defp generate_with_tools(model, history, tools, req_http_options) do
      with {:ok, response} <- generate_initial_response(model, history, tools, req_http_options),
           text <- Response.text(response),
           tool_calls <- extract_tool_calls(response) do
        handle_tool_calls(model, history, tools, req_http_options, text, tool_calls)
      end
    end

    defp generate_initial_response(model, history, tools, req_http_options) do
      ReqLLM.generate_text(
        model,
        history.messages,
        tools: tools,
        max_tokens: 1024,
        req_http_options: req_http_options
      )
    end

    defp handle_tool_calls(_model, history, _tools, _req_http_options, text, []) do
      # No tools called, we're done
      final_history = Context.append(history, Context.assistant(text))
      {:ok, final_history, text}
    end

    defp handle_tool_calls(model, history, tools, req_http_options, text, tool_calls) do
      assistant_message = Context.assistant(text, tool_calls: tool_calls)
      history_with_tool_call = Context.append(history, assistant_message)

      tool_result_messages = execute_tool_calls(tool_calls, tools)

      history_with_results = Context.append(history_with_tool_call, tool_result_messages)

      generate_final_response(model, history_with_results, req_http_options)
    end

    defp execute_tool_calls(tool_calls, tools) do
      Enum.map(tool_calls, fn tool_call ->
        execute_single_tool(tool_call, tools)
      end)
    end

    defp execute_single_tool(tool_call, tools) do
      tool = Enum.find(tools, fn t -> t.name == tool_call.name end)

      case tool do
        nil ->
          result = %{error: "Tool not found"}
          Context.tool_result(tool_call.id, tool_call.name, Jason.encode!(result))

        tool ->
          case Tool.execute(tool, tool_call.arguments) do
            {:ok, result} ->
              result_str = if is_binary(result), do: result, else: Jason.encode!(result)
              Context.tool_result(tool_call.id, tool_call.name, result_str)

            {:error, error} ->
              error_result = %{error: "Tool execution failed: #{inspect(error)}"}
              Context.tool_result(tool_call.id, tool_call.name, Jason.encode!(error_result))
          end
      end
    end

    defp generate_final_response(model, history_with_results, req_http_options) do
      case ReqLLM.generate_text(
             model,
             history_with_results.messages,
             max_tokens: 1024,
             req_http_options: req_http_options
           ) do
        {:ok, final_response} ->
          final_text = Response.text(final_response)
          final_history = Context.append(history_with_results, Context.assistant(final_text))
          {:ok, final_history, final_text}

        {:error, error} ->
          {:error, error}
      end
    end

    defp extract_tool_calls(response) do
      case response.message do
        %Message{tool_calls: tool_calls} when is_list(tool_calls) and length(tool_calls) > 0 ->
          Enum.map(tool_calls, fn tool_call ->
            %{
              id: tool_call.id,
              name: ToolCall.name(tool_call),
              arguments: ToolCall.args_map(tool_call) || %{}
            }
          end)

        _ ->
          []
      end
    end

    defp setup_tools do
      [
        Tool.new!(
          name: "calculator",
          description: "Perform mathematical calculations. Pass an expression string.",
          parameter_schema: [
            expression: [
              type: :string,
              required: true,
              doc: "Mathematical expression to evaluate. Examples: '15 * 7', '10 + 5', 'sqrt(16)'"
            ]
          ],
          callback: &calculator_callback/1
        ),
        Tool.new!(
          name: "web_search",
          description: "Search the web for information",
          parameter_schema: [
            query: [type: :string, required: true, doc: "Search query"]
          ],
          callback: fn %{"query" => query} ->
            {:ok, "Mock search results for: #{query}"}
          end
        )
      ]
    end

    defp calculator_callback(%{"expression" => expr}) when is_binary(expr) do
      {result, _} = Code.eval_string(expr)
      {:ok, result}
    rescue
      e -> {:error, "Invalid expression: #{Exception.message(e)}"}
    end

    defp calculator_callback(%{expression: expr}) when is_binary(expr) do
      {result, _} = Code.eval_string(expr)
      {:ok, result}
    rescue
      e -> {:error, "Invalid expression: #{Exception.message(e)}"}
    end

    defp calculator_callback(args) do
      {:error,
       "Provide an expression string. Example: {\"expression\":\"15 * 7\"}. Got: #{inspect(args)}"}
    end
  end

  describe "Agent cassette replay" do
    @tag :req_llm
    @tag :capture_log
    test "single prompt with tool should replay correctly" do
      # Use named cassette so we can switch modes between calls
      cassette_opts_record = %{
        cassette_dir: @cassette_dir,
        cassette_name: "agent_single_prompt",
        mode: :record,
        filter_request_headers: ["authorization", "x-api-key", "cookie"]
      }

      cassette_opts_replay = %{
        cassette_dir: @cassette_dir,
        cassette_name: "agent_single_prompt",
        mode: :replay
      }

      Logger.debug("=== FIRST RUN ===")
      {:ok, agent1} = MyAgentWithCassettes.start_link(cassette_opts: cassette_opts_record)
      {:ok, response1} = MyAgentWithCassettes.prompt(agent1, "What is 15 * 7?")
      Logger.debug("First response: #{response1}")

      cassettes_after_first = File.ls!(@cassette_dir)
      Logger.debug("Cassettes after first run: #{length(cassettes_after_first)}")

      # Verify cassette interactions after first call
      cassette_path = Path.join(@cassette_dir, "agent_single_prompt.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)
      interactions_count = length(cassette["interactions"])
      Logger.debug("Interactions after first run: #{interactions_count}")

      Logger.debug("=== SECOND RUN (replay) ===")
      {:ok, agent2} = MyAgentWithCassettes.start_link(cassette_opts: cassette_opts_replay)
      {:ok, response2} = MyAgentWithCassettes.prompt(agent2, "What is 15 * 7?")
      Logger.debug("Second response: #{response2}")

      cassettes_after_second = File.ls!(@cassette_dir)
      Logger.debug("Cassettes after second run: #{length(cassettes_after_second)}")

      # Verify responses are identical
      assert response1 == response2

      # Verify no new cassettes were created
      assert length(cassettes_after_second) == length(cassettes_after_first),
             "New cassettes were created on replay. Expected: #{length(cassettes_after_first)}, Got: #{length(cassettes_after_second)}"

      # Verify interaction count unchanged (replay didn't add new interactions)
      {:ok, data_after} = File.read(cassette_path)
      {:ok, cassette_after} = Jason.decode(data_after)

      assert length(cassette_after["interactions"]) == interactions_count,
             "Interactions changed on replay. Expected: #{interactions_count}, Got: #{length(cassette_after["interactions"])}"
    end

    @tag :req_llm
    @tag :capture_log
    test "multiple prompts should replay correctly from same agent" do
      # Use named cassette so we can switch modes between calls
      cassette_opts_record = %{
        cassette_dir: @cassette_dir,
        cassette_name: "agent_multiple_prompts",
        mode: :record,
        filter_request_headers: ["authorization", "x-api-key", "cookie"]
      }

      cassette_opts_replay = %{
        cassette_dir: @cassette_dir,
        cassette_name: "agent_multiple_prompts",
        mode: :replay
      }

      Logger.debug("=== FIRST RUN - Multiple prompts ===")
      {:ok, agent1} = MyAgentWithCassettes.start_link(cassette_opts: cassette_opts_record)

      {:ok, response1a} = MyAgentWithCassettes.prompt(agent1, "What is 15 * 7?")
      Logger.debug("First prompt response: #{response1a}")

      {:ok, response1b} =
        MyAgentWithCassettes.prompt(
          agent1,
          "Write a short poem that includes the result of 234 - 167"
        )

      Logger.debug("Second prompt response: #{response1b}")

      cassettes_after_first = File.ls!(@cassette_dir)
      Logger.debug("Cassettes after first run: #{length(cassettes_after_first)}")

      # Verify cassette interactions after first call
      cassette_path = Path.join(@cassette_dir, "agent_multiple_prompts.json")
      {:ok, data} = File.read(cassette_path)
      {:ok, cassette} = Jason.decode(data)
      interactions_count = length(cassette["interactions"])
      Logger.debug("Interactions after first run: #{interactions_count}")

      Logger.debug("=== SECOND RUN (replay) - Same prompts ===")
      {:ok, agent2} = MyAgentWithCassettes.start_link(cassette_opts: cassette_opts_replay)

      {:ok, response2a} = MyAgentWithCassettes.prompt(agent2, "What is 15 * 7?")
      Logger.debug("First prompt response (replay): #{response2a}")

      {:ok, response2b} =
        MyAgentWithCassettes.prompt(
          agent2,
          "Write a short poem that includes the result of 234 - 167"
        )

      Logger.debug("Second prompt response (replay): #{response2b}")

      cassettes_after_second = File.ls!(@cassette_dir)
      Logger.debug("Cassettes after second run: #{length(cassettes_after_second)}")

      # Verify responses are identical
      assert response1a == response2a
      assert response1b == response2b

      # Verify no new cassettes were created
      assert length(cassettes_after_second) == length(cassettes_after_first),
             "New cassettes were created on replay. Expected: #{length(cassettes_after_first)}, Got: #{length(cassettes_after_second)}"

      # Verify interaction count unchanged (replay didn't add new interactions)
      {:ok, data_after} = File.read(cassette_path)
      {:ok, cassette_after} = Jason.decode(data_after)

      assert length(cassette_after["interactions"]) == interactions_count,
             "Interactions changed on replay. Expected: #{interactions_count}, Got: #{length(cassette_after["interactions"])}"
    end
  end
end
