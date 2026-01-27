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
  """

  @uuid_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  @uri_regex ~r/^https?:\/\//
  @date_regex ~r/^\d{4}-\d{2}-\d{2}$/
  @datetime_regex ~r/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}/

  # Maximum recursion depth to prevent stack overflow on deeply nested structures
  @max_depth 50

  @type json_schema :: map()

  @doc """
  Infers a JSON Schema from an Elixir value.

  An optional `depth` parameter limits recursion to prevent stack overflow
  on deeply nested structures. When max depth is reached, returns an empty
  schema for nested values.

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
  @spec infer(term(), non_neg_integer()) :: json_schema()
  def infer(value, depth \\ 0)

  # Stop recursion at max depth to prevent stack overflow
  def infer(_value, depth) when depth >= @max_depth, do: %{}

  def infer(nil, _depth), do: %{"type" => "null"}

  def infer(value, _depth) when is_binary(value) do
    %{"type" => "string"}
    |> maybe_add_format(value)
  end

  def infer(value, _depth) when is_integer(value), do: %{"type" => "integer"}

  def infer(value, _depth) when is_float(value), do: %{"type" => "number"}

  def infer(value, _depth) when is_boolean(value), do: %{"type" => "boolean"}

  def infer(value, depth) when is_list(value) do
    %{
      "type" => "array",
      "items" => infer_array_items(value, depth + 1)
    }
  end

  def infer(value, depth) when is_map(value) do
    %{
      "type" => "object",
      "properties" => infer_properties(value, depth + 1)
    }
  end

  def infer(value, _depth) when is_tuple(value), do: %{"type" => "array"}
  def infer(value, _depth) when is_atom(value), do: %{"type" => "string"}
  def infer(_value, _depth), do: %{}

  @doc """
  Merges multiple schemas into one, combining their properties.

  This is useful when the same endpoint returns slightly different
  response shapes in different tests.

  ## Example

      iex> TypeInferrer.merge_schemas([schema1, schema2])
      %{"type" => "object", "properties" => %{...combined...}}
  """
  @spec merge_schemas(list(json_schema())) :: json_schema()
  def merge_schemas([]), do: %{}
  def merge_schemas([schema]), do: schema

  def merge_schemas(schemas) do
    schemas
    |> Enum.reduce(%{}, &deep_merge_schema/2)
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

  defp infer_array_items([], _depth), do: %{}

  defp infer_array_items(items, depth) when is_list(items) do
    items
    |> Enum.map(&infer(&1, depth))
    |> merge_schemas()
  end

  defp infer_array_items(_, _depth), do: %{}

  defp infer_properties(map, depth) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      {to_string(key), infer(value, depth)}
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

  defp deep_merge_schema(schema1, schema2, depth \\ 0)

  # Stop recursion at max depth
  defp deep_merge_schema(_schema1, schema2, depth) when depth >= @max_depth, do: schema2

  defp deep_merge_schema(schema1, schema2, depth) when is_map(schema1) and is_map(schema2) do
    Map.merge(schema1, schema2, fn
      "properties", props1, props2 when is_map(props1) and is_map(props2) ->
        Map.merge(props1, props2, fn _k, v1, v2 -> deep_merge_schema(v1, v2, depth + 1) end)

      "items", items1, items2 when is_map(items1) and is_map(items2) ->
        deep_merge_schema(items1, items2, depth + 1)

      _key, _v1, v2 ->
        v2
    end)
  end

  defp deep_merge_schema(_schema1, schema2, _depth), do: schema2
end
