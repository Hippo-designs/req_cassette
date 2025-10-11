# Exclude LLM tests by default (require API keys and cost money)
# Run them with: mix test --include req_llm
ExUnit.start(exclude: [:req_llm])
