defmodule ExUnitOpenAPI.Generator do
  @moduledoc """
  Generates OpenAPI 3.0 specifications from collected request/response data.

  This module takes the captured HTTP interactions from the Collector and
  transforms them into a valid OpenAPI specification, using the RouterAnalyzer
  to map requests to route patterns and the TypeInferrer to generate schemas.

  ## Schema Deduplication

  When `schema_deduplication: true` (default), identical schemas are
  automatically deduplicated using `$ref` pointers to `components/schemas`.
  Schema names are either inferred from context or can be overridden via
  config or test tags.
  """

  alias ExUnitOpenAPI.{Config, RouterAnalyzer, SchemaRegistry, TypeInferrer}

  @openapi_version "3.0.3"

  @type spec :: map()

  @doc """
  Generates an OpenAPI specification from collected request data.

  ## Parameters

  - `collected_data` - List of captured request/response data from Collector
  - `config` - Configuration map from Config module

  ## Returns

  - `{:ok, spec}` - The generated OpenAPI specification as a map
  - `{:error, reason}` - If generation fails
  """
  @spec generate(list(map()), Config.t()) :: {:ok, spec()} | {:error, term()}
  def generate(collected_data, config) do
    router = Config.router(config)
    routes = if router, do: RouterAnalyzer.analyze(router), else: []

    # Initialize the schema registry
    registry = SchemaRegistry.new(config)

    # Build paths and collect schemas in registry
    {paths, registry} = build_paths(collected_data, routes, registry, config)

    # Finalize registry to get components.schemas
    schemas = SchemaRegistry.finalize(registry)

    spec = %{
      "openapi" => @openapi_version,
      "info" => build_info(config),
      "paths" => paths,
      "components" => build_components(schemas, config)
    }

    spec =
      spec
      |> maybe_add_servers(config)
      |> maybe_merge_existing(config)

    {:ok, spec}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Private functions - Info

  defp build_info(config) do
    info = Config.info(config)

    %{
      "title" => Map.get(info, :title, "API"),
      "version" => Map.get(info, :version, "1.0.0")
    }
    |> maybe_add("description", Map.get(info, :description))
    |> maybe_add("termsOfService", Map.get(info, :terms_of_service))
    |> maybe_add("contact", Map.get(info, :contact))
    |> maybe_add("license", Map.get(info, :license))
  end

  # Private functions - Servers

  defp maybe_add_servers(spec, config) do
    case Config.servers(config) do
      [] -> spec
      servers -> Map.put(spec, "servers", servers)
    end
  end

  # Private functions - Paths

  defp build_paths(collected_data, routes, registry, config) do
    grouped = group_by_endpoint(collected_data, routes)

    {path_operations, registry} =
      Enum.reduce(grouped, {[], registry}, fn {{path_pattern, method}, requests}, {acc, reg} ->
        openapi_path = RouterAnalyzer.to_openapi_path(path_pattern)
        {operation, reg} = build_operation(method, path_pattern, requests, routes, reg, config)
        {[{openapi_path, %{String.downcase(method) => operation}} | acc], reg}
      end)

    paths =
      path_operations
      |> merge_path_operations()
      |> Enum.into(%{})

    {paths, registry}
  end

  defp group_by_endpoint(collected_data, routes) do
    collected_data
    |> Enum.group_by(fn request ->
      case RouterAnalyzer.match_route(request.path, request.method, routes) do
        {:ok, route, _params} -> {route.path, request.method}
        :no_match -> {request.path, request.method}
      end
    end)
  end

  defp merge_path_operations(path_operations) do
    path_operations
    |> Enum.group_by(fn {path, _ops} -> path end, fn {_path, ops} -> ops end)
    |> Enum.map(fn {path, ops_list} ->
      merged_ops = Enum.reduce(ops_list, %{}, &Map.merge/2)
      {path, merged_ops}
    end)
  end

  defp build_operation(method, path_pattern, requests, routes, registry, config) do
    route_info = find_route_info(path_pattern, method, routes)

    # Build context for schema naming
    base_context = build_schema_context(route_info, method, path_pattern, requests)

    # Build responses with registry
    {responses, registry} = build_responses(requests, base_context, registry, config)

    operation = %{
      "operationId" => generate_operation_id(route_info, method, path_pattern),
      "responses" => responses
    }

    # Add request body (may register schemas)
    {operation, registry} =
      maybe_add_request_body(operation, method, requests, base_context, registry, config)

    operation =
      operation
      |> maybe_add_parameters(path_pattern, requests)
      |> maybe_add_tags(route_info)

    {operation, registry}
  end

  defp build_schema_context(route_info, method, path_pattern, requests) do
    # Extract openapi tags from requests if present
    openapi_tags =
      requests
      |> Enum.find_value(fn req ->
        Map.get(req, :openapi_tags)
      end)

    base = %{
      method: method,
      path: path_pattern,
      openapi_tags: openapi_tags
    }

    if route_info do
      Map.merge(base, %{
        controller: route_info.controller,
        action: route_info.action
      })
    else
      base
    end
  end

  defp find_route_info(path_pattern, method, routes) do
    Enum.find(routes, fn route ->
      route.path == path_pattern && route.method == method
    end)
  end

  defp generate_operation_id(nil, method, path) do
    # Generate from path when no route info available
    path
    |> String.replace(~r/[:\{\}\/]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
    |> then(&"#{String.downcase(method)}_#{&1}")
  end

  defp generate_operation_id(route_info, _method, _path) do
    controller_name =
      route_info.controller
      |> Module.split()
      |> List.last()
      |> String.replace("Controller", "")

    "#{controller_name}.#{route_info.action}"
  end

  # Private functions - Parameters

  defp maybe_add_parameters(operation, path_pattern, requests) do
    path_params = build_path_parameters(path_pattern, requests)
    query_params = build_query_parameters(requests)

    case path_params ++ query_params do
      [] -> operation
      params -> Map.put(operation, "parameters", params)
    end
  end

  defp build_path_parameters(path_pattern, requests) do
    param_names = RouterAnalyzer.extract_path_params(path_pattern)

    param_names
    |> Enum.map(fn param_name ->
      # Get example values from requests
      example_values =
        requests
        |> Enum.flat_map(fn req -> Map.get(req.path_params, param_name, []) |> List.wrap() end)
        |> Enum.uniq()

      schema =
        case example_values do
          [first | _] -> TypeInferrer.infer_param_type(first)
          [] -> %{"type" => "string"}
        end

      %{
        "name" => param_name,
        "in" => "path",
        "required" => true,
        "schema" => schema
      }
    end)
  end

  defp build_query_parameters(requests) do
    requests
    |> Enum.flat_map(fn req -> Map.keys(req.query_params) end)
    |> Enum.uniq()
    |> Enum.map(fn param_name ->
      example_values =
        requests
        |> Enum.flat_map(fn req ->
          case Map.get(req.query_params, param_name) do
            nil -> []
            value -> [value]
          end
        end)
        |> Enum.uniq()

      schema =
        case example_values do
          [first | _] -> TypeInferrer.infer_param_type(first)
          [] -> %{"type" => "string"}
        end

      %{
        "name" => param_name,
        "in" => "query",
        "required" => false,
        "schema" => schema
      }
    end)
  end

  # Private functions - Request Body

  defp maybe_add_request_body(operation, method, requests, context, registry, config)
       when method in ["POST", "PUT", "PATCH"] do
    body_values =
      requests
      |> Enum.map(& &1.body_params)
      |> Enum.reject(&(map_size(&1) == 0))

    case body_values do
      [] ->
        {operation, registry}

      values ->
        # Use infer_merged for proper enum detection
        merged_schema = TypeInferrer.infer_merged(values, enum_opts(config))

        # Register the request body schema
        request_context = Map.put(context, :type, :request)

        {registry, schema_or_ref} =
          SchemaRegistry.register(registry, merged_schema, request_context, top_level: true)

        # Process nested schemas for potential extraction
        {registry, processed_schema} =
          if is_ref?(schema_or_ref) do
            {registry, schema_or_ref}
          else
            process_nested_schemas(registry, schema_or_ref, request_context, config)
          end

        request_body = %{
          "required" => true,
          "content" => %{
            "application/json" => %{
              "schema" => processed_schema
            }
          }
        }

        {Map.put(operation, "requestBody", request_body), registry}
    end
  end

  defp maybe_add_request_body(operation, _method, _requests, _context, registry, _config) do
    {operation, registry}
  end

  # Private functions - Responses

  defp build_responses(requests, base_context, registry, config) do
    grouped = Enum.group_by(requests, & &1.response_status)

    Enum.reduce(grouped, {%{}, registry}, fn {status, status_requests}, {acc, reg} ->
      response_context =
        base_context
        |> Map.put(:type, :response)
        |> Map.put(:status, status)

      {response, reg} = build_response(status, status_requests, response_context, reg, config)
      {Map.put(acc, Integer.to_string(status), response), reg}
    end)
  end

  defp build_response(status, requests, context, registry, config) do
    response = %{
      "description" => status_description(status)
    }

    # Build content schema from response bodies
    body_values =
      requests
      |> Enum.map(& &1.response_body)
      |> Enum.reject(&is_nil/1)

    case body_values do
      [] ->
        {response, registry}

      values ->
        # Use infer_merged for proper enum detection
        merged_schema = TypeInferrer.infer_merged(values, enum_opts(config))

        # Register the response body schema
        {registry, schema_or_ref} =
          SchemaRegistry.register(registry, merged_schema, context, top_level: true)

        # Process nested schemas for potential extraction
        {registry, processed_schema} =
          if is_ref?(schema_or_ref) do
            {registry, schema_or_ref}
          else
            process_nested_schemas(registry, schema_or_ref, context, config)
          end

        response_with_content =
          Map.put(response, "content", %{
            "application/json" => %{
              "schema" => processed_schema
            }
          })

        {response_with_content, registry}
    end
  end

  defp process_nested_schemas(registry, schema, context, _config) do
    SchemaRegistry.process_nested(registry, schema, context)
  end

  defp is_ref?(%{"$ref" => _}), do: true
  defp is_ref?(_), do: false

  # Extract enum inference options from config
  defp enum_opts(config) do
    [
      enum_inference: Map.get(config, :enum_inference, true),
      enum_min_samples: Map.get(config, :enum_min_samples, 3),
      enum_max_values: Map.get(config, :enum_max_values, 10)
    ]
  end

  defp status_description(200), do: "Successful response"
  defp status_description(201), do: "Resource created"
  defp status_description(204), do: "No content"
  defp status_description(400), do: "Bad request"
  defp status_description(401), do: "Unauthorized"
  defp status_description(403), do: "Forbidden"
  defp status_description(404), do: "Not found"
  defp status_description(422), do: "Unprocessable entity"
  defp status_description(500), do: "Internal server error"
  defp status_description(status), do: "Response #{status}"

  # Private functions - Tags

  defp maybe_add_tags(operation, nil), do: operation

  defp maybe_add_tags(operation, route_info) do
    tag =
      route_info.controller
      |> Module.split()
      |> List.last()
      |> String.replace("Controller", "")

    Map.put(operation, "tags", [tag])
  end

  # Private functions - Components

  defp build_components(schemas, config) do
    components = %{}

    # Add schemas from registry
    components =
      if map_size(schemas) > 0 do
        Map.put(components, "schemas", schemas)
      else
        components
      end

    # Add security schemes from config
    case Config.security_schemes(config) do
      schemes when map_size(schemes) > 0 ->
        Map.put(components, "securitySchemes", schemes)

      _ ->
        components
    end
  end

  # Private functions - Merge existing

  defp maybe_merge_existing(spec, config) do
    if Config.merge_with_existing?(config) do
      output_path = Config.output_path(config)

      case File.read(output_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, existing} -> deep_merge_spec(existing, spec)
            {:error, _} -> spec
          end

        {:error, _} ->
          spec
      end
    else
      spec
    end
  end

  defp deep_merge_spec(existing, new) do
    Map.merge(existing, new, fn
      "paths", existing_paths, new_paths ->
        Map.merge(existing_paths, new_paths, fn _path, existing_ops, new_ops ->
          Map.merge(existing_ops, new_ops)
        end)

      "components", existing_components, new_components ->
        Map.merge(existing_components, new_components, fn _key, existing_val, new_val ->
          Map.merge(existing_val, new_val)
        end)

      _key, _existing_val, new_val ->
        new_val
    end)
  end

  # Private functions - Helpers

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
