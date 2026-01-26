defmodule ExUnitOpenAPI.SchemaRegistryTest do
  use ExUnit.Case, async: true

  alias ExUnitOpenAPI.SchemaRegistry

  defmodule TestApp.UserController do
    # Dummy module for testing
  end

  @default_config %{
    schema_deduplication: true,
    schema_names: %{},
    extract_single_use: false,
    min_properties_for_extraction: 3
  }

  describe "new/1" do
    test "creates a new registry with config" do
      registry = SchemaRegistry.new(@default_config)
      assert registry.config == @default_config
      assert registry.schemas == %{}
      assert registry.names == %{}
    end
  end

  describe "register/4 - top level schemas" do
    test "extracts top-level response schema and returns $ref" do
      registry = SchemaRegistry.new(@default_config)

      schema = %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "integer"},
          "name" => %{"type" => "string"}
        }
      }

      context = %{
        controller: TestApp.UserController,
        action: :show,
        type: :response,
        status: 200
      }

      {registry, result} = SchemaRegistry.register(registry, schema, context, top_level: true)

      assert %{"$ref" => ref} = result
      assert String.starts_with?(ref, "#/components/schemas/")
      assert map_size(registry.schemas) == 1
    end

    test "returns same $ref for identical schemas" do
      registry = SchemaRegistry.new(@default_config)

      schema = %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "integer"},
          "name" => %{"type" => "string"}
        }
      }

      context1 = %{
        controller: TestApp.UserController,
        action: :show,
        type: :response,
        status: 200
      }

      context2 = %{
        controller: TestApp.UserController,
        action: :index,
        type: :response,
        status: 200
      }

      {registry, ref1} = SchemaRegistry.register(registry, schema, context1, top_level: true)
      {_registry, ref2} = SchemaRegistry.register(registry, schema, context2, top_level: true)

      assert ref1 == ref2
    end

    test "returns different $ref for different schemas" do
      registry = SchemaRegistry.new(@default_config)

      schema1 = %{"type" => "object", "properties" => %{"id" => %{"type" => "integer"}}}
      schema2 = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}

      context1 = %{controller: TestApp.UserController, action: :show, type: :response, status: 200}
      context2 = %{controller: TestApp.UserController, action: :index, type: :response, status: 200}

      {registry, ref1} = SchemaRegistry.register(registry, schema1, context1, top_level: true)
      {_registry, ref2} = SchemaRegistry.register(registry, schema2, context2, top_level: true)

      refute ref1 == ref2
    end
  end

  describe "register/4 - deduplication disabled" do
    test "returns schema as-is when deduplication disabled" do
      config = Map.put(@default_config, :schema_deduplication, false)
      registry = SchemaRegistry.new(config)

      schema = %{"type" => "object", "properties" => %{"id" => %{"type" => "integer"}}}
      context = %{controller: TestApp.UserController, action: :show, type: :response, status: 200}

      {_registry, result} = SchemaRegistry.register(registry, schema, context, top_level: true)

      assert result == schema
    end
  end

  describe "register/4 - empty schemas" do
    test "returns empty schema unchanged" do
      registry = SchemaRegistry.new(@default_config)
      context = %{controller: TestApp.UserController, action: :show, type: :response, status: 200}

      {_registry, result} = SchemaRegistry.register(registry, %{}, context, top_level: true)

      assert result == %{}
    end
  end

  describe "register/4 - force_inline option" do
    test "inlines schema when force_inline is true" do
      registry = SchemaRegistry.new(@default_config)

      schema = %{"type" => "object", "properties" => %{"id" => %{"type" => "integer"}}}
      context = %{controller: TestApp.UserController, action: :show, type: :response, status: 200}

      {_registry, result} =
        SchemaRegistry.register(registry, schema, context, top_level: true, force_inline: true)

      assert result == schema
    end
  end

  describe "finalize/1" do
    test "returns map of named schemas" do
      registry = SchemaRegistry.new(@default_config)

      schema = %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "integer"},
          "name" => %{"type" => "string"}
        }
      }

      context = %{controller: TestApp.UserController, action: :show, type: :response, status: 200}

      {registry, _ref} = SchemaRegistry.register(registry, schema, context, top_level: true)
      components = SchemaRegistry.finalize(registry)

      assert map_size(components) == 1
      assert Enum.any?(components, fn {_name, s} -> s == schema end)
    end

    test "returns empty map when no schemas registered" do
      registry = SchemaRegistry.new(@default_config)
      components = SchemaRegistry.finalize(registry)

      assert components == %{}
    end
  end

  describe "process_nested/3" do
    test "processes nested object properties" do
      registry = SchemaRegistry.new(@default_config)

      schema = %{
        "type" => "object",
        "properties" => %{
          "user" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "integer"},
              "name" => %{"type" => "string"}
            }
          }
        }
      }

      context = %{controller: TestApp.UserController, action: :show, type: :response, status: 200}

      {_registry, processed} = SchemaRegistry.process_nested(registry, schema, context)

      # Should return processed schema (structure preserved)
      assert processed["type"] == "object"
      assert processed["properties"]["user"]["type"] == "object"
    end

    test "processes array items" do
      registry = SchemaRegistry.new(@default_config)

      schema = %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "integer"}
          }
        }
      }

      context = %{controller: TestApp.UserController, action: :index, type: :response, status: 200}

      {_registry, processed} = SchemaRegistry.process_nested(registry, schema, context)

      assert processed["type"] == "array"
      assert processed["items"]["type"] == "object"
    end
  end

  describe "register_reusable/3" do
    test "always extracts schema and returns $ref" do
      registry = SchemaRegistry.new(@default_config)

      schema = %{"type" => "object", "properties" => %{"id" => %{"type" => "integer"}}}
      context = %{controller: TestApp.UserController, action: :show, type: :response, status: 200}

      {registry, result} = SchemaRegistry.register_reusable(registry, schema, context)

      assert %{"$ref" => _} = result
      assert map_size(registry.schemas) == 1
    end
  end
end
