defmodule ExUnitOpenAPI.SchemaFingerprintTest do
  use ExUnit.Case, async: true

  alias ExUnitOpenAPI.SchemaFingerprint

  describe "fingerprint/1" do
    test "returns a 64-character hex string" do
      fingerprint = SchemaFingerprint.fingerprint(%{"type" => "string"})
      assert is_binary(fingerprint)
      assert String.length(fingerprint) == 64
      assert Regex.match?(~r/^[0-9a-f]+$/, fingerprint)
    end

    test "identical schemas produce identical fingerprints" do
      schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}

      fp1 = SchemaFingerprint.fingerprint(schema)
      fp2 = SchemaFingerprint.fingerprint(schema)

      assert fp1 == fp2
    end

    test "property order does not affect fingerprint" do
      schema1 = %{
        "type" => "object",
        "properties" => %{
          "a" => %{"type" => "string"},
          "b" => %{"type" => "integer"},
          "c" => %{"type" => "boolean"}
        }
      }

      schema2 = %{
        "type" => "object",
        "properties" => %{
          "c" => %{"type" => "boolean"},
          "a" => %{"type" => "string"},
          "b" => %{"type" => "integer"}
        }
      }

      assert SchemaFingerprint.fingerprint(schema1) == SchemaFingerprint.fingerprint(schema2)
    end

    test "different schemas produce different fingerprints" do
      schema1 = %{"type" => "string"}
      schema2 = %{"type" => "integer"}

      refute SchemaFingerprint.fingerprint(schema1) == SchemaFingerprint.fingerprint(schema2)
    end

    test "nested schema property order does not affect fingerprint" do
      schema1 = %{
        "type" => "object",
        "properties" => %{
          "user" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"},
              "email" => %{"type" => "string"}
            }
          }
        }
      }

      schema2 = %{
        "type" => "object",
        "properties" => %{
          "user" => %{
            "type" => "object",
            "properties" => %{
              "email" => %{"type" => "string"},
              "name" => %{"type" => "string"}
            }
          }
        }
      }

      assert SchemaFingerprint.fingerprint(schema1) == SchemaFingerprint.fingerprint(schema2)
    end

    test "array items are fingerprinted correctly" do
      schema = %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "integer"},
            "name" => %{"type" => "string"}
          }
        }
      }

      fp1 = SchemaFingerprint.fingerprint(schema)
      fp2 = SchemaFingerprint.fingerprint(schema)

      assert fp1 == fp2
    end

    test "handles empty schema" do
      fp = SchemaFingerprint.fingerprint(%{})
      assert is_binary(fp)
      assert String.length(fp) == 64
    end

    test "handles non-map input" do
      assert SchemaFingerprint.fingerprint(nil) == ""
      assert SchemaFingerprint.fingerprint("string") == ""
      assert SchemaFingerprint.fingerprint([]) == ""
    end
  end

  describe "same?/2" do
    test "returns true for identical schemas" do
      schema = %{"type" => "string"}
      assert SchemaFingerprint.same?(schema, schema)
    end

    test "returns true for schemas with different property order" do
      schema1 = %{"properties" => %{"a" => %{}, "b" => %{}}, "type" => "object"}
      schema2 = %{"type" => "object", "properties" => %{"b" => %{}, "a" => %{}}}

      assert SchemaFingerprint.same?(schema1, schema2)
    end

    test "returns false for different schemas" do
      schema1 = %{"type" => "string"}
      schema2 = %{"type" => "integer"}

      refute SchemaFingerprint.same?(schema1, schema2)
    end
  end
end
