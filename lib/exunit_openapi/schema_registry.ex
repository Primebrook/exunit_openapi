defmodule ExUnitOpenAPI.SchemaRegistry do
  @moduledoc """
  Central registry for schema deduplication and $ref generation.

  The SchemaRegistry tracks all schemas encountered during spec generation,
  identifies duplicates by fingerprint, and generates `$ref` pointers to
  shared schema definitions in `components/schemas`.

  ## How It Works

  1. When a schema is registered, its fingerprint is computed
  2. If a schema with the same fingerprint exists, return a `$ref` to it
  3. If it's new, decide whether to extract or inline based on thresholds
  4. At finalization, build the `components/schemas` map

  ## Extraction Rules

  By default, schemas are extracted (get a name and $ref) when:
  - They are top-level request/response bodies (always)
  - They are nested objects with 3+ properties used 2+ times
  - They are array item schemas used 2+ times

  ## Example

      registry = SchemaRegistry.new(config)
      {registry, ref_or_schema} = SchemaRegistry.register(registry, schema, context)
      components_schemas = SchemaRegistry.finalize(registry)
  """

  alias ExUnitOpenAPI.{SchemaFingerprint, SchemaNamer}

  defstruct [
    :config,
    # fingerprint -> %{schema: ..., name: ..., usage_count: ...}
    schemas: %{},
    # name -> fingerprint (reverse lookup)
    names: %{},
    # For SchemaNamer collision resolution
    name_state: nil
  ]

  @type t :: %__MODULE__{
          config: map(),
          schemas: %{String.t() => map()},
          names: %{String.t() => String.t()},
          name_state: SchemaNamer.name_state()
        }

  @type context :: SchemaNamer.context()

  @doc """
  Creates a new SchemaRegistry with the given config.
  """
  @spec new(map()) :: t()
  def new(config) do
    %__MODULE__{
      config: config,
      schemas: %{},
      names: %{},
      name_state: SchemaNamer.new_state()
    }
  end

  @doc """
  Registers a schema and returns either the schema itself or a `$ref`.

  For top-level schemas (request/response bodies), always extracts to a named
  schema and returns a `$ref`. For nested schemas, applies extraction rules
  based on config thresholds.

  ## Parameters

  - `registry` - The SchemaRegistry
  - `schema` - The JSON Schema to register
  - `context` - Context for naming (controller, action, type, etc.)
  - `opts` - Options:
    - `:top_level` - Whether this is a top-level body (default: false)
    - `:force_inline` - Never extract this schema (default: false)

  ## Returns

  `{updated_registry, schema_or_ref}` where `schema_or_ref` is either:
  - The original schema (if inlined)
  - A `$ref` map like `%{"$ref" => "#/components/schemas/User"}`
  """
  @spec register(t(), map(), context(), keyword()) :: {t(), map()}
  def register(registry, schema, context, opts \\ [])

  def register(registry, schema, _context, _opts) when schema == %{} do
    {registry, schema}
  end

  def register(registry, schema, context, opts) do
    top_level = Keyword.get(opts, :top_level, false)
    force_inline = Keyword.get(opts, :force_inline, false)

    if force_inline or not deduplication_enabled?(registry.config) do
      {registry, schema}
    else
      fingerprint = SchemaFingerprint.fingerprint(schema)

      case Map.get(registry.schemas, fingerprint) do
        nil ->
          # New schema - decide whether to extract
          if should_extract?(schema, top_level, registry.config) do
            register_new_schema(registry, schema, fingerprint, context)
          else
            # Track but inline
            registry = track_schema(registry, schema, fingerprint, nil)
            {registry, schema}
          end

        %{name: nil} ->
          # Previously inlined, now seen again - maybe extract now?
          existing = Map.get(registry.schemas, fingerprint)
          new_count = existing.usage_count + 1

          if should_extract_on_reuse?(schema, new_count, registry.config) do
            # Promote to named schema
            register_new_schema(registry, schema, fingerprint, context)
          else
            registry = update_usage_count(registry, fingerprint, new_count)
            {registry, schema}
          end

        %{name: name} ->
          # Already registered with name - return $ref
          registry = increment_usage(registry, fingerprint)
          {registry, make_ref(name)}
      end
    end
  end

  @doc """
  Registers a schema that should always be extracted (for nested schemas
  that are known to be reusable).

  Similar to `register/4` with `top_level: true`.
  """
  @spec register_reusable(t(), map(), context()) :: {t(), map()}
  def register_reusable(registry, schema, context) do
    register(registry, schema, context, top_level: true)
  end

  @doc """
  Finalizes the registry and returns the `components/schemas` map.

  Only includes schemas that have been extracted (have a name).
  """
  @spec finalize(t()) :: map()
  def finalize(registry) do
    registry.schemas
    |> Enum.filter(fn {_fingerprint, data} -> data.name != nil end)
    |> Enum.map(fn {_fingerprint, data} -> {data.name, data.schema} end)
    |> Enum.into(%{})
  end

  @doc """
  Processes a schema tree, registering nested schemas that should be extracted.

  Walks through the schema recursively, extracting nested object schemas
  and array item schemas according to the extraction rules.

  ## Returns

  `{updated_registry, processed_schema}` where nested schemas may have
  been replaced with `$ref` pointers.
  """
  @spec process_nested(t(), map(), context()) :: {t(), map()}
  def process_nested(registry, schema, context)

  def process_nested(registry, %{"type" => "object", "properties" => props} = schema, context)
      when is_map(props) do
    {registry, processed_props} =
      Enum.reduce(props, {registry, %{}}, fn {key, prop_schema}, {reg, acc} ->
        nested_context = Map.put(context, :property_name, key)
        {reg, processed} = process_nested(reg, prop_schema, nested_context)
        {reg, Map.put(acc, key, processed)}
      end)

    {registry, %{schema | "properties" => processed_props}}
  end

  def process_nested(registry, %{"type" => "array", "items" => items} = schema, context)
      when is_map(items) do
    # Array items that are objects might be worth extracting
    item_context = Map.put(context, :is_array_item, true)
    {registry, processed_items} = maybe_extract_array_items(registry, items, item_context)
    {registry, %{schema | "items" => processed_items}}
  end

  def process_nested(registry, schema, _context) do
    {registry, schema}
  end

  # Private functions

  defp deduplication_enabled?(config) do
    Map.get(config, :schema_deduplication, true)
  end

  defp should_extract?(schema, true, _config) do
    # Top-level schemas are always extracted (if not empty)
    map_size(schema) > 0
  end

  defp should_extract?(schema, false, config) do
    min_props = Map.get(config, :min_properties_for_extraction, 3)
    extract_single_use = Map.get(config, :extract_single_use, false)

    case schema do
      %{"type" => "object", "properties" => props} when is_map(props) ->
        extract_single_use or map_size(props) >= min_props

      _ ->
        extract_single_use
    end
  end

  defp should_extract_on_reuse?(schema, usage_count, config) do
    min_uses = 2
    min_props = Map.get(config, :min_properties_for_extraction, 3)

    usage_count >= min_uses and
      case schema do
        %{"type" => "object", "properties" => props} when is_map(props) ->
          map_size(props) >= min_props

        %{"type" => "array"} ->
          true

        _ ->
          false
      end
  end

  defp register_new_schema(registry, schema, fingerprint, context) do
    {name, name_state} = SchemaNamer.generate(context, registry.config, registry.name_state)

    registry = %{
      registry
      | schemas:
          Map.put(registry.schemas, fingerprint, %{
            schema: schema,
            name: name,
            usage_count: 1
          }),
        names: Map.put(registry.names, name, fingerprint),
        name_state: name_state
    }

    {registry, make_ref(name)}
  end

  defp track_schema(registry, schema, fingerprint, name) do
    %{
      registry
      | schemas:
          Map.put(registry.schemas, fingerprint, %{
            schema: schema,
            name: name,
            usage_count: 1
          })
    }
  end

  defp update_usage_count(registry, fingerprint, count) do
    %{
      registry
      | schemas:
          Map.update!(registry.schemas, fingerprint, fn data ->
            %{data | usage_count: count}
          end)
    }
  end

  defp increment_usage(registry, fingerprint) do
    %{
      registry
      | schemas:
          Map.update!(registry.schemas, fingerprint, fn data ->
            %{data | usage_count: data.usage_count + 1}
          end)
    }
  end

  defp maybe_extract_array_items(registry, items, context) do
    case items do
      %{"type" => "object", "properties" => props} when is_map(props) ->
        # Check if this object schema should be extracted
        fingerprint = SchemaFingerprint.fingerprint(items)

        case Map.get(registry.schemas, fingerprint) do
          nil ->
            # First time seeing this - track it
            registry = track_schema(registry, items, fingerprint, nil)
            {registry, items}

          %{name: nil, usage_count: count} ->
            # Seen before but not named - now we have 2+ uses, extract it
            if count >= 1 do
              register_new_schema(registry, items, fingerprint, context)
            else
              registry = update_usage_count(registry, fingerprint, count + 1)
              {registry, items}
            end

          %{name: name} ->
            # Already extracted - return ref
            registry = increment_usage(registry, fingerprint)
            {registry, make_ref(name)}
        end

      _ ->
        {registry, items}
    end
  end

  defp make_ref(name) do
    %{"$ref" => "#/components/schemas/#{name}"}
  end
end
