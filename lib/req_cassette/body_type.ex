defmodule ReqCassette.BodyType do
  @moduledoc """
  Detects and handles different body types for optimal cassette storage.

  This module provides intelligent body type detection and encoding/decoding to ensure
  cassettes are human-readable, compact, and easy to edit. It distinguishes between
  three body types based on content-type headers and content analysis.

  ## Body Types

  ### `:json` - JSON Data

  JSON responses are stored as native Elixir data structures in the `body_json` field.
  When the cassette is saved, Jason pretty-prints the JSON for readability.

  **Benefits:**
  - No double-encoding or escaping
  - Compact cassette files
  - Human-readable without string escape sequences
  - Easy to manually edit cassettes

  **Example storage:**
  ```json
  "body_json": {
    "id": 1,
    "name": "Alice",
    "roles": ["admin", "user"]
  }
  ```

  ### `:text` - Plain Text

  Text responses (HTML, XML, CSV, plain text) are stored as strings in the `body` field.

  **Examples:**
  - HTML pages
  - XML documents
  - CSV data
  - Plain text files
  - YAML/TOML configs

  **Example storage:**
  ```json
  "body": "<html><head><title>Page</title></head><body>...</body></html>"
  ```

  ### `:blob` - Binary Data

  Binary responses (images, PDFs, videos) are base64-encoded in the `body_blob` field.

  **Examples:**
  - PNG/JPEG images
  - PDF documents
  - ZIP archives
  - Protocol buffers
  - MessagePack data

  **Example storage:**
  ```json
  "body_blob": "iVBORw0KGgoAAAANSUhEUgAAAAUA..."
  ```

  ## Detection Algorithm

  The module uses a multi-step detection process:

  1. **Content-Type Header** - Check for explicit type hints
     - `application/json` → `:json`
     - `text/*` → `:text`
     - `image/*` → `:blob`

  2. **Already Decoded** - If Req already decoded the body to a map/list → `:json`

  3. **JSON Parsing** - Attempt to parse as JSON, if successful → `:json`

  4. **Printability Check** - Use `String.printable?/1`:
     - Printable → `:text`
     - Non-printable → `:blob`

  This ensures accurate detection even when content-type headers are missing or incorrect.

  ## Usage

  This module is used internally by `ReqCassette.Cassette` when adding interactions:

      # Automatic type detection and encoding
      body_type = BodyType.detect_type(response.body, response.headers)
      {field, value} = BodyType.encode(response.body, body_type)

      # Later, when replaying
      decoded_body = BodyType.decode(cassette_response)

  You typically don't need to use this module directly - it's called automatically
  by the cassette system.

  ## Examples

      # JSON Detection
      detect_type(~s({"key": "value"}), %{"content-type" => ["application/json"]})
      #=> :json

      detect_type(%{"id" => 1}, %{})  # Already decoded by Req
      #=> :json

      # Text Detection
      detect_type("<html><body>Hello</body></html>", %{"content-type" => ["text/html"]})
      #=> :text

      detect_type("name,age\\nAlice,30", %{"content-type" => ["text/csv"]})
      #=> :text

      # Blob Detection
      detect_type(<<137, 80, 78, 71, 13, 10, 26, 10>>, %{"content-type" => ["image/png"]})
      #=> :blob

      detect_type(<<255, 216, 255, 224>>, %{})  # Non-printable = blob
      #=> :blob

      # Encoding for storage
      encode(%{"id" => 1, "name" => "Alice"}, :json)
      #=> {"body_json", %{"id" => 1, "name" => "Alice"}}

      encode("<html></html>", :text)
      #=> {"body", "<html></html>"}

      encode(<<137, 80, 78, 71>>, :blob)
      #=> {"body_blob", "iVBORw=="}

      # Decoding from cassette
      decode(%{"body_type" => "json", "body_json" => %{"id" => 1}})
      #=> ~s({"id":1})

      decode(%{"body_type" => "text", "body" => "<html></html>"})
      #=> "<html></html>"

      decode(%{"body_type" => "blob", "body_blob" => "iVBORw=="})
      #=> <<137, 80, 78, 71>>
  """

  @type body_type :: :json | :text | :blob

  @doc """
  Detects the body type from content and headers.

  Detection algorithm:
  1. Check content-type header for hints
  2. For empty bodies, return :text
  3. Try parsing as JSON
  4. Check if string is printable (text vs binary)
  5. Default to :blob for binary data

  ## Parameters

  - `body` - The body content (string or binary)
  - `headers` - HTTP headers map (lowercase keys)

  ## Returns

  Body type: `:json`, `:text`, or `:blob`

  ## Examples

      detect_type("", %{})
      # => :text

      detect_type(~s({"id": 1}), %{"content-type" => ["application/json"]})
      # => :json

      detect_type("<html></html>", %{"content-type" => ["text/html"]})
      # => :text

      detect_type(<<137, 80, 78, 71>>, %{"content-type" => ["image/png"]})
      # => :blob
  """
  @spec detect_type(binary() | map() | list(), map()) :: body_type()
  def detect_type(body, headers)

  # Empty body
  def detect_type("", _headers), do: :text
  def detect_type(nil, _headers), do: :text

  # Already decoded by Req (map or list) - it's JSON
  def detect_type(body, _headers) when is_map(body) or is_list(body), do: :json

  # Binary body - detect based on content-type and content analysis
  def detect_type(body, headers) when is_binary(body) do
    content_type = get_content_type(headers)

    cond do
      # Check content-type header first
      json_content_type?(content_type) ->
        # Verify it's actually valid JSON
        case Jason.decode(body) do
          {:ok, _} -> :json
          {:error, _} -> :text
        end

      binary_content_type?(content_type) ->
        :blob

      text_content_type?(content_type) ->
        :text

      # No content-type or ambiguous - analyze content
      true ->
        detect_from_content(body)
    end
  end

  # Fallback for other types
  def detect_type(_body, _headers), do: :text

  @doc """
  Encodes body for cassette storage based on its type.

  ## Parameters

  - `body` - The body content
  - `body_type` - The detected body type (`:json`, `:text`, or `:blob`)

  ## Returns

  Tuple of `{field_name, encoded_value}` where:
  - `:json` → `{"body_json", decoded_map_or_list}`
  - `:text` → `{"body", string}`
  - `:blob` → `{"body_blob", base64_string}`

  ## Examples

      encode(~s({"id": 1}), :json)
      # => {"body_json", %{"id" => 1}}

      encode("<html></html>", :text)
      # => {"body", "<html></html>"}

      encode(<<137, 80, 78, 71>>, :blob)
      # => {"body_blob", "iVBORw0K..."}
  """
  @spec encode(binary() | map() | list(), body_type()) :: {String.t(), term()}
  def encode(body, body_type)

  def encode(body, :json) when is_map(body) or is_list(body) do
    # Already decoded
    {"body_json", body}
  end

  def encode(body, :json) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {"body_json", decoded}
      {:error, _} -> {"body", body}
    end
  end

  def encode(body, :text) when is_binary(body) do
    {"body", body}
  end

  def encode(body, :blob) when is_binary(body) do
    {"body_blob", Base.encode64(body)}
  end

  def encode(body, _type) do
    # Fallback: try to convert to string
    {"body", to_string(body)}
  end

  @doc """
  Decodes body from cassette storage.

  ## Parameters

  - `cassette_response` - The response map from cassette with body_type and body fields

  ## Returns

  Decoded body as binary string

  ## Examples

      decode(%{"body_type" => "json", "body_json" => %{"id" => 1}})
      # => ~s({"id":1})

      decode(%{"body_type" => "text", "body" => "<html></html>"})
      # => "<html></html>"

      decode(%{"body_type" => "blob", "body_blob" => "iVBORw0K..."})
      # => <<137, 80, 78, 71, ...>>
  """
  @spec decode(map()) :: binary()
  def decode(cassette_response)

  def decode(%{"body_type" => "json", "body_json" => body_json}) do
    Jason.encode!(body_json)
  end

  def decode(%{"body_type" => "text", "body" => body}) do
    body
  end

  def decode(%{"body_type" => "blob", "body_blob" => body_blob}) do
    Base.decode64!(body_blob)
  end

  # Backward compatibility with v0.1 format (no body_type field)
  def decode(%{"body" => body}) when is_binary(body) do
    body
  end

  # Fallback
  def decode(_), do: ""

  # Private helpers

  defp get_content_type(headers) do
    headers
    |> Enum.find_value(fn
      {k, v} when k in ["content-type", "Content-Type"] ->
        case v do
          [first | _] -> first
          v when is_binary(v) -> v
          _ -> nil
        end

      _ ->
        nil
    end)
    |> case do
      nil -> ""
      ct -> String.downcase(ct)
    end
  end

  defp json_content_type?(content_type) do
    String.contains?(content_type, "json") or
      String.contains?(content_type, "application/ld+json")
  end

  defp binary_content_type?(content_type) do
    prefixes = [
      "image/",
      "video/",
      "audio/",
      "application/octet-stream",
      "application/pdf",
      "application/zip",
      "application/gzip",
      "application/x-tar",
      "application/protobuf",
      "application/msgpack"
    ]

    Enum.any?(prefixes, &String.starts_with?(content_type, &1))
  end

  defp text_content_type?(content_type) do
    String.starts_with?(content_type, "text/") or
      content_type in [
        "application/xml",
        "application/xhtml+xml",
        "application/atom+xml",
        "application/rss+xml",
        "application/x-www-form-urlencoded"
      ]
  end

  defp detect_from_content(body) do
    cond do
      # Try to parse as JSON
      match?({:ok, _}, Jason.decode(body)) ->
        :json

      # Check if it's printable text
      String.printable?(body) ->
        :text

      # Binary data
      true ->
        :blob
    end
  end
end
