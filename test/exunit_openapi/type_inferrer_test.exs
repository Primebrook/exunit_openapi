defmodule ExUnitOpenAPI.TypeInferrerTest do
  use ExUnit.Case, async: true

  alias ExUnitOpenAPI.TypeInferrer

  describe "infer/1" do
    test "infers null type" do
      assert TypeInferrer.infer(nil) == %{"type" => "null"}
    end

    test "infers string type" do
      assert TypeInferrer.infer("hello") == %{"type" => "string"}
    end

    test "infers integer type" do
      assert TypeInferrer.infer(42) == %{"type" => "integer"}
    end

    test "infers number type for floats" do
      assert TypeInferrer.infer(3.14) == %{"type" => "number"}
    end

    test "infers boolean type" do
      assert TypeInferrer.infer(true) == %{"type" => "boolean"}
      assert TypeInferrer.infer(false) == %{"type" => "boolean"}
    end

    test "infers array type" do
      result = TypeInferrer.infer([1, 2, 3])
      assert result["type"] == "array"
      assert result["items"]["type"] == "integer"
    end

    test "infers object type" do
      result = TypeInferrer.infer(%{"name" => "Alice", "age" => 30})
      assert result["type"] == "object"
      assert result["properties"]["name"]["type"] == "string"
      assert result["properties"]["age"]["type"] == "integer"
    end

    test "infers nested object types" do
      result = TypeInferrer.infer(%{
        "user" => %{
          "name" => "Alice",
          "address" => %{
            "city" => "London"
          }
        }
      })

      assert result["type"] == "object"
      assert result["properties"]["user"]["type"] == "object"
      assert result["properties"]["user"]["properties"]["address"]["type"] == "object"
      assert result["properties"]["user"]["properties"]["address"]["properties"]["city"]["type"] == "string"
    end
  end

  describe "string format detection" do
    test "detects UUID format" do
      result = TypeInferrer.infer("550e8400-e29b-41d4-a716-446655440000")
      assert result == %{"type" => "string", "format" => "uuid"}
    end

    test "detects date-time format" do
      result = TypeInferrer.infer("2024-01-15T10:30:00Z")
      assert result == %{"type" => "string", "format" => "date-time"}
    end

    test "detects date format" do
      result = TypeInferrer.infer("2024-01-15")
      assert result == %{"type" => "string", "format" => "date"}
    end

    test "detects email format" do
      result = TypeInferrer.infer("user@example.com")
      assert result == %{"type" => "string", "format" => "email"}
    end

    test "detects URI format" do
      result = TypeInferrer.infer("https://example.com/path")
      assert result == %{"type" => "string", "format" => "uri"}
    end
  end

  describe "infer_param_type/1" do
    test "detects integer strings" do
      assert TypeInferrer.infer_param_type("123") == %{"type" => "integer"}
    end

    test "detects float strings" do
      assert TypeInferrer.infer_param_type("3.14") == %{"type" => "number"}
    end

    test "detects boolean strings" do
      assert TypeInferrer.infer_param_type("true") == %{"type" => "boolean"}
      assert TypeInferrer.infer_param_type("false") == %{"type" => "boolean"}
    end

    test "defaults to string for other values" do
      assert TypeInferrer.infer_param_type("hello") == %{"type" => "string"}
    end
  end

  describe "merge_schemas/1" do
    test "returns empty map for empty list" do
      assert TypeInferrer.merge_schemas([]) == %{}
    end

    test "returns single schema unchanged" do
      schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
      assert TypeInferrer.merge_schemas([schema]) == schema
    end

    test "merges properties from multiple schemas" do
      schema1 = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
      schema2 = %{"type" => "object", "properties" => %{"age" => %{"type" => "integer"}}}

      result = TypeInferrer.merge_schemas([schema1, schema2])

      assert result["type"] == "object"
      assert result["properties"]["name"]["type"] == "string"
      assert result["properties"]["age"]["type"] == "integer"
    end
  end
end
