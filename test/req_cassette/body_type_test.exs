defmodule ReqCassette.BodyTypeTest do
  use ExUnit.Case, async: true

  alias ReqCassette.BodyType

  describe "detect_type/2" do
    test "detects JSON from content-type header" do
      body = ~s({"id": 1, "name": "Alice"})
      headers = %{"content-type" => ["application/json"]}

      assert BodyType.detect_type(body, headers) == :json
    end

    test "detects JSON with charset in content-type" do
      body = ~s({"id": 1})
      headers = %{"content-type" => ["application/json; charset=utf-8"]}

      assert BodyType.detect_type(body, headers) == :json
    end

    test "detects JSON from content analysis when no content-type" do
      body = ~s({"id": 1, "name": "Alice"})
      headers = %{}

      assert BodyType.detect_type(body, headers) == :json
    end

    test "detects JSON from already-decoded map" do
      body = %{"id" => 1, "name" => "Alice"}
      headers = %{}

      assert BodyType.detect_type(body, headers) == :json
    end

    test "detects JSON from already-decoded list" do
      body = [%{"id" => 1}, %{"id" => 2}]
      headers = %{}

      assert BodyType.detect_type(body, headers) == :json
    end

    test "detects text from text/html content-type" do
      body = "<html><body>Hello</body></html>"
      headers = %{"content-type" => ["text/html"]}

      assert BodyType.detect_type(body, headers) == :text
    end

    test "detects text from text/plain content-type" do
      body = "Hello, world!"
      headers = %{"content-type" => ["text/plain"]}

      assert BodyType.detect_type(body, headers) == :text
    end

    test "detects text from application/xml content-type" do
      body = "<?xml version=\"1.0\"?><root></root>"
      headers = %{"content-type" => ["application/xml"]}

      assert BodyType.detect_type(body, headers) == :text
    end

    test "detects text from printable content" do
      body = "Plain text content"
      headers = %{}

      assert BodyType.detect_type(body, headers) == :text
    end

    test "detects blob from image/png content-type" do
      body = <<137, 80, 78, 71, 13, 10, 26, 10>>
      headers = %{"content-type" => ["image/png"]}

      assert BodyType.detect_type(body, headers) == :blob
    end

    test "detects blob from image/jpeg content-type" do
      body = <<255, 216, 255, 224>>
      headers = %{"content-type" => ["image/jpeg"]}

      assert BodyType.detect_type(body, headers) == :blob
    end

    test "detects blob from application/pdf content-type" do
      body = "%PDF-1.4\n"
      headers = %{"content-type" => ["application/pdf"]}

      assert BodyType.detect_type(body, headers) == :blob
    end

    test "detects blob from binary content" do
      body = <<0, 1, 2, 3, 255, 254, 253>>
      headers = %{}

      assert BodyType.detect_type(body, headers) == :blob
    end

    test "detects text for empty body" do
      assert BodyType.detect_type("", %{}) == :text
      assert BodyType.detect_type(nil, %{}) == :text
    end

    test "handles Content-Type with capital letters" do
      body = ~s({"id": 1})
      headers = %{"Content-Type" => ["application/json"]}

      assert BodyType.detect_type(body, headers) == :json
    end

    test "handles invalid JSON with json content-type as text" do
      body = "{invalid json"
      headers = %{"content-type" => ["application/json"]}

      assert BodyType.detect_type(body, headers) == :text
    end
  end

  describe "encode/2" do
    test "encodes JSON from decoded map" do
      body = %{"id" => 1, "name" => "Alice"}

      assert BodyType.encode(body, :json) == {"body_json", %{"id" => 1, "name" => "Alice"}}
    end

    test "encodes JSON from decoded list" do
      body = [%{"id" => 1}, %{"id" => 2}]

      assert BodyType.encode(body, :json) == {"body_json", [%{"id" => 1}, %{"id" => 2}]}
    end

    test "encodes JSON from string" do
      body = ~s({"id": 1, "name": "Alice"})

      {field, value} = BodyType.encode(body, :json)
      assert field == "body_json"
      assert value == %{"id" => 1, "name" => "Alice"}
    end

    test "encodes text as string" do
      body = "<html><body>Hello</body></html>"

      assert BodyType.encode(body, :text) == {"body", "<html><body>Hello</body></html>"}
    end

    test "encodes blob as base64" do
      body = <<137, 80, 78, 71, 13, 10, 26, 10>>

      {field, value} = BodyType.encode(body, :blob)
      assert field == "body_blob"
      assert is_binary(value)
      assert Base.decode64!(value) == body
    end

    test "handles invalid JSON gracefully" do
      body = "{invalid json"

      assert BodyType.encode(body, :json) == {"body", "{invalid json"}
    end
  end

  describe "decode/1" do
    test "decodes JSON body" do
      cassette = %{
        "body_type" => "json",
        "body_json" => %{"id" => 1, "name" => "Alice"}
      }

      result = BodyType.decode(cassette)
      decoded = Jason.decode!(result)
      assert decoded == %{"id" => 1, "name" => "Alice"}
    end

    test "decodes text body" do
      cassette = %{
        "body_type" => "text",
        "body" => "<html><body>Hello</body></html>"
      }

      assert BodyType.decode(cassette) == "<html><body>Hello</body></html>"
    end

    test "decodes blob body" do
      original = <<137, 80, 78, 71, 13, 10, 26, 10>>
      encoded = Base.encode64(original)

      cassette = %{
        "body_type" => "blob",
        "body_blob" => encoded
      }

      assert BodyType.decode(cassette) == original
    end

    test "handles backward compatibility with v0.1 format" do
      cassette = %{"body" => ~s({"id": 1})}

      assert BodyType.decode(cassette) == ~s({"id": 1})
    end

    test "returns empty string for invalid cassette" do
      assert BodyType.decode(%{}) == ""
      assert BodyType.decode(%{"body_type" => "unknown"}) == ""
    end
  end

  describe "round-trip encoding and decoding" do
    test "JSON body round-trip" do
      original = %{"id" => 1, "name" => "Alice", "tags" => ["admin", "user"]}

      {field, encoded} = BodyType.encode(original, :json)
      cassette = %{"body_type" => "json", field => encoded}
      decoded = BodyType.decode(cassette)
      final = Jason.decode!(decoded)

      assert final == original
    end

    test "Text body round-trip" do
      original = "<html><body>Hello</body></html>"

      {field, encoded} = BodyType.encode(original, :text)
      cassette = %{"body_type" => "text", field => encoded}
      decoded = BodyType.decode(cassette)

      assert decoded == original
    end

    test "Blob body round-trip" do
      original = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 255, 128>>

      {field, encoded} = BodyType.encode(original, :blob)
      cassette = %{"body_type" => "blob", field => encoded}
      decoded = BodyType.decode(cassette)

      assert decoded == original
    end
  end
end
