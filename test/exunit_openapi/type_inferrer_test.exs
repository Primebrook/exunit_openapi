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

    test "adds nullable when null type is present" do
      schema1 = %{"type" => "string"}
      schema2 = %{"type" => "null"}

      result = TypeInferrer.merge_schemas([schema1, schema2])

      assert result["type"] == "string"
      assert result["nullable"] == true
    end

    test "handles all nulls" do
      schema1 = %{"type" => "null"}
      schema2 = %{"type" => "null"}

      result = TypeInferrer.merge_schemas([schema1, schema2])
      assert result == %{}
    end

    test "uses oneOf for mixed types" do
      schema1 = %{"type" => "string"}
      schema2 = %{"type" => "integer"}

      result = TypeInferrer.merge_schemas([schema1, schema2])

      assert result["oneOf"] != nil
      assert length(result["oneOf"]) == 2
    end
  end

  describe "infer_with_samples/2" do
    test "returns empty map for empty samples" do
      assert TypeInferrer.infer_with_samples([]) == %{}
    end

    test "infers basic type from samples" do
      result = TypeInferrer.infer_with_samples([1, 2, 3])
      assert result["type"] == "integer"
    end

    test "infers enum for repeated string values" do
      samples = ["pending", "active", "pending", "completed", "active"]
      result = TypeInferrer.infer_with_samples(samples)

      assert result["type"] == "string"
      assert result["enum"] == ["active", "completed", "pending"]
    end

    test "does not infer enum with too few samples" do
      samples = ["a", "b"]
      result = TypeInferrer.infer_with_samples(samples, enum_min_samples: 3)

      assert result["type"] == "string"
      refute Map.has_key?(result, "enum")
    end

    test "does not infer enum when all values are unique" do
      samples = ["a", "b", "c", "d", "e"]
      result = TypeInferrer.infer_with_samples(samples)

      assert result["type"] == "string"
      refute Map.has_key?(result, "enum")
    end

    test "does not infer enum when too many unique values" do
      samples = Enum.map(1..20, &"value#{&1}")
      result = TypeInferrer.infer_with_samples(samples, enum_max_values: 10)

      assert result["type"] == "string"
      refute Map.has_key?(result, "enum")
    end

    test "handles nullable with enum" do
      samples = ["active", nil, "pending", "active", nil]
      result = TypeInferrer.infer_with_samples(samples)

      assert result["type"] == "string"
      assert result["nullable"] == true
      assert result["enum"] == ["active", "pending"]
    end

    test "can disable enum inference" do
      samples = ["a", "b", "a", "b"]
      result = TypeInferrer.infer_with_samples(samples, enum_inference: false)

      assert result["type"] == "string"
      refute Map.has_key?(result, "enum")
    end
  end

  describe "array items with mixed types" do
    test "uses oneOf for genuinely mixed array items" do
      result = TypeInferrer.infer(["hello", 42, "world"])

      assert result["type"] == "array"
      assert result["items"]["oneOf"] != nil
    end

    test "uses nullable for string + null array items" do
      result = TypeInferrer.infer(["hello", nil, "world"])

      assert result["type"] == "array"
      assert result["items"]["type"] == "string"
      assert result["items"]["nullable"] == true
    end
  end

  describe "infer_merged/2" do
    test "returns empty map for empty list" do
      assert TypeInferrer.infer_merged([]) == %{}
    end

    test "returns single inferred schema for single value" do
      result = TypeInferrer.infer_merged([%{"name" => "Alice"}])
      assert result["type"] == "object"
      assert result["properties"]["name"]["type"] == "string"
    end

    test "detects enums in object properties" do
      values = [
        %{"status" => "pending", "name" => "Alice"},
        %{"status" => "active", "name" => "Bob"},
        %{"status" => "pending", "name" => "Charlie"}
      ]

      result = TypeInferrer.infer_merged(values)

      assert result["type"] == "object"
      assert result["properties"]["status"]["type"] == "string"
      assert result["properties"]["status"]["enum"] == ["active", "pending"]
      assert result["properties"]["name"]["type"] == "string"
      refute Map.has_key?(result["properties"]["name"], "enum")
    end

    test "handles nested objects" do
      values = [
        %{"user" => %{"role" => "admin"}},
        %{"user" => %{"role" => "user"}},
        %{"user" => %{"role" => "admin"}}
      ]

      result = TypeInferrer.infer_merged(values)

      user_schema = result["properties"]["user"]
      assert user_schema["type"] == "object"
      assert user_schema["properties"]["role"]["enum"] == ["admin", "user"]
    end

    test "marks optional properties as nullable" do
      values = [
        %{"name" => "Alice", "email" => "alice@test.com"},
        %{"name" => "Bob"}  # No email
      ]

      result = TypeInferrer.infer_merged(values)

      assert result["properties"]["name"]["type"] == "string"
      refute Map.has_key?(result["properties"]["name"], "nullable")
      assert result["properties"]["email"]["type"] == "string"
      assert result["properties"]["email"]["nullable"] == true
    end

    test "handles arrays of objects" do
      values = [
        [%{"status" => "pending"}, %{"status" => "active"}],
        [%{"status" => "pending"}]
      ]

      result = TypeInferrer.infer_merged(values)

      assert result["type"] == "array"
      assert result["items"]["properties"]["status"]["enum"] == ["active", "pending"]
    end

    test "respects enum_inference option" do
      values = [
        %{"status" => "pending"},
        %{"status" => "active"},
        %{"status" => "pending"}
      ]

      result = TypeInferrer.infer_merged(values, enum_inference: false)

      assert result["properties"]["status"]["type"] == "string"
      refute Map.has_key?(result["properties"]["status"], "enum")
    end
  end
end
