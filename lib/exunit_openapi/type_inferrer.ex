defmodule ExUnitOpenAPI.TypeInferrer do
  @moduledoc """
  Infers JSON Schema types from Elixir values.

  This module analyzes captured request/response data and generates
  JSON Schema type definitions for use in OpenAPI specifications.

  ## Type Inference Rules

  - `nil` → `{"type": "null"}` or marks field as nullable
  - Strings → `{"type": "string"}` with optional format detection
  - Integers → `{"type": "integer"}`
  - Floats → `{"type": "number"}`
  - Booleans → `{"type": "boolean"}`
  - Lists → `{"type": "array", "items": ...}`
  - Maps → `{"type": "object", "properties": ...}`

  ## Format Detection

  String values are analyzed for common patterns:
  - ISO 8601 dates → `{"type": "string", "format": "date-time"}`
  - UUIDs → `{"type": "string", "format": "uuid"}`
  - Email addresses → `{"type": "string", "format": "email"}`
  - URIs → `{"type": "string", "format": "uri"}`

  ## Nullable Detection

  When merging schemas, if any value is null, the merged schema gets
  `"nullable": true` (OpenAPI 3.0 style).

  ## Enum Inference

  When `infer_with_samples/2` is used with multiple sample values for
  a string field, and there are few unique values, an enum is inferred.
  """

  @uuid_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  @uri_regex ~r/^https?:\/\//
  @date_regex ~r/^\d{4}-\d{2}-\d{2}$/
  @datetime_regex ~r/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}/

  @type json_schema :: map()

  @doc """
  Infers a JSON Schema from an Elixir value.

  ## Examples

      iex> TypeInferrer.infer(42)
      %{"type" => "integer"}

      iex> TypeInferrer.infer(%{"name" => "Alice", "age" => 30})
      %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        }
      }
  """
  @spec infer(term()) :: json_schema()
  def infer(nil), do: %{"type" => "null"}

  def infer(value) when is_binary(value) do
    %{"type" => "string"}
    |> maybe_add_format(value)
  end

  def infer(value) when is_integer(value), do: %{"type" => "integer"}

  def infer(value) when is_float(value), do: %{"type" => "number"}

  def infer(value) when is_boolean(value), do: %{"type" => "boolean"}

  def infer(value) when is_list(value) do
    %{
      "type" => "array",
      "items" => infer_array_items(value)
    }
  end

  def infer(value) when is_map(value) do
    %{
      "type" => "object",
      "properties" => infer_properties(value)
    }
  end

  def infer(value) when is_tuple(value), do: %{"type" => "array"}
  def infer(value) when is_atom(value), do: %{"type" => "string"}
  def infer(_value), do: %{}

  @doc """
  Merges multiple schemas into one, combining their properties.

  This is useful when the same endpoint returns slightly different
  response shapes in different tests.

  When one of the schemas is a null type, the merged result will have
  `"nullable": true` added.

  ## Example

      iex> TypeInferrer.merge_schemas([schema1, schema2])
      %{"type" => "object", "properties" => %{...combined...}}

      iex> TypeInferrer.merge_schemas([%{"type" => "string"}, %{"type" => "null"}])
      %{"type" => "string", "nullable" => true}
  """
  @spec merge_schemas(list(json_schema())) :: json_schema()
  def merge_schemas([]), do: %{}
  def merge_schemas([schema]), do: schema

  def merge_schemas(schemas) do
    has_null = Enum.any?(schemas, &(&1["type"] == "null"))
    non_null_schemas = Enum.reject(schemas, &(&1["type"] == "null"))

    merged =
      case non_null_schemas do
        [] -> %{}
        [single] -> single
        multiple -> merge_non_null_schemas(multiple)
      end

    if has_null and merged != %{} do
      Map.put(merged, "nullable", true)
    else
      merged
    end
  end

  @doc """
  Infers a schema from multiple sample values, potentially detecting enums.

  When given multiple string samples with a limited set of unique values,
  this function can infer an enum type.

  ## Options

  - `:enum_inference` - Enable enum detection (default: true)
  - `:enum_min_samples` - Minimum samples needed to consider enum (default: 3)
  - `:enum_max_values` - Maximum unique values to be considered an enum (default: 10)

  ## Examples

      iex> TypeInferrer.infer_with_samples(["pending", "active", "pending", "completed"])
      %{"type" => "string", "enum" => ["active", "completed", "pending"]}

      iex> TypeInferrer.infer_with_samples([1, 2, 3])
      %{"type" => "integer"}
  """
  @spec infer_with_samples(list(term()), keyword()) :: json_schema()
  def infer_with_samples(samples, opts \\ [])

  def infer_with_samples([], _opts), do: %{}

  def infer_with_samples(samples, opts) do
    enum_inference = Keyword.get(opts, :enum_inference, true)
    enum_min_samples = Keyword.get(opts, :enum_min_samples, 3)
    enum_max_values = Keyword.get(opts, :enum_max_values, 10)

    # First, get the basic merged schema
    schemas = Enum.map(samples, &infer/1)
    base_schema = merge_schemas(schemas)

    # Check if we should infer an enum
    if enum_inference and base_schema["type"] == "string" do
      non_nil_samples = Enum.reject(samples, &is_nil/1)
      unique_values = non_nil_samples |> Enum.uniq() |> Enum.sort()

      if length(non_nil_samples) >= enum_min_samples and
           length(unique_values) <= enum_max_values and
           length(unique_values) < length(non_nil_samples) do
        Map.put(base_schema, "enum", unique_values)
      else
        base_schema
      end
    else
      base_schema
    end
  end

  @doc """
  Infers the type of a path or query parameter from its string value.

  Attempts to detect if the string represents an integer, boolean, etc.

  ## Examples

      iex> TypeInferrer.infer_param_type("123")
      %{"type" => "integer"}

      iex> TypeInferrer.infer_param_type("true")
      %{"type" => "boolean"}

      iex> TypeInferrer.infer_param_type("hello")
      %{"type" => "string"}
  """
  @spec infer_param_type(String.t()) :: json_schema()
  def infer_param_type(value) when is_binary(value) do
    cond do
      integer_string?(value) -> %{"type" => "integer"}
      float_string?(value) -> %{"type" => "number"}
      boolean_string?(value) -> %{"type" => "boolean"}
      true -> %{"type" => "string"} |> maybe_add_format(value)
    end
  end

  def infer_param_type(value), do: infer(value)

  # Private functions

  defp infer_array_items([]), do: %{}

  defp infer_array_items(items) when is_list(items) do
    schemas = Enum.map(items, &infer/1)

    # Check if we have genuinely mixed types (not just nullable)
    types = schemas |> Enum.map(&Map.get(&1, "type")) |> Enum.uniq()
    non_null_types = Enum.reject(types, &(&1 == "null"))

    case non_null_types do
      [] ->
        # All nulls
        %{}

      [_single_type] ->
        # Single type (possibly with null) - use merge_schemas for nullable handling
        merge_schemas(schemas)

      _multiple_types ->
        # Genuinely mixed types - use oneOf
        non_null_schemas = Enum.reject(schemas, &(&1["type"] == "null"))
        unique_schemas = Enum.uniq(non_null_schemas)

        if Enum.any?(schemas, &(&1["type"] == "null")) do
          %{"oneOf" => unique_schemas, "nullable" => true}
        else
          %{"oneOf" => unique_schemas}
        end
    end
  end

  defp infer_array_items(_), do: %{}

  # Merge multiple non-null schemas, handling mixed types with oneOf
  defp merge_non_null_schemas(schemas) do
    types = schemas |> Enum.map(&Map.get(&1, "type")) |> Enum.uniq()

    case types do
      [_single_type] ->
        # All same type - deep merge
        Enum.reduce(schemas, %{}, &deep_merge_schema/2)

      _multiple_types ->
        # Mixed types - use oneOf
        %{"oneOf" => Enum.uniq(schemas)}
    end
  end

  defp infer_properties(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      {to_string(key), infer(value)}
    end)
    |> Enum.into(%{})
  end

  defp maybe_add_format(schema, value) do
    cond do
      Regex.match?(@uuid_regex, value) ->
        Map.put(schema, "format", "uuid")

      Regex.match?(@datetime_regex, value) ->
        Map.put(schema, "format", "date-time")

      Regex.match?(@date_regex, value) ->
        Map.put(schema, "format", "date")

      Regex.match?(@email_regex, value) ->
        Map.put(schema, "format", "email")

      Regex.match?(@uri_regex, value) ->
        Map.put(schema, "format", "uri")

      true ->
        schema
    end
  end

  defp integer_string?(value) do
    case Integer.parse(value) do
      {_int, ""} -> true
      _ -> false
    end
  end

  defp float_string?(value) do
    case Float.parse(value) do
      {_float, ""} -> true
      _ -> false
    end
  end

  defp boolean_string?(value) when value in ["true", "false"], do: true
  defp boolean_string?(_), do: false

  defp deep_merge_schema(schema1, schema2) when is_map(schema1) and is_map(schema2) do
    Map.merge(schema1, schema2, fn
      "properties", props1, props2 when is_map(props1) and is_map(props2) ->
        Map.merge(props1, props2, fn _k, v1, v2 -> deep_merge_schema(v1, v2) end)

      "items", items1, items2 when is_map(items1) and is_map(items2) ->
        deep_merge_schema(items1, items2)

      _key, _v1, v2 ->
        v2
    end)
  end

  defp deep_merge_schema(_schema1, schema2), do: schema2
end
