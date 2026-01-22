defmodule ExUnitOpenAPI.Generator do
  @moduledoc """
  Generates OpenAPI 3.0 specifications from collected request/response data.

  This module takes the captured HTTP interactions from the Collector and
  transforms them into a valid OpenAPI specification, using the RouterAnalyzer
  to map requests to route patterns and the TypeInferrer to generate schemas.
  """

  alias ExUnitOpenAPI.{Config, RouterAnalyzer, TypeInferrer}

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

    spec = %{
      "openapi" => @openapi_version,
      "info" => build_info(config),
      "paths" => build_paths(collected_data, routes),
      "components" => build_components(collected_data, config)
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

  defp build_paths(collected_data, routes) do
    collected_data
    |> group_by_endpoint(routes)
    |> Enum.map(fn {{path_pattern, method}, requests} ->
      openapi_path = RouterAnalyzer.to_openapi_path(path_pattern)
      operation = build_operation(method, path_pattern, requests, routes)
      {openapi_path, %{String.downcase(method) => operation}}
    end)
    |> merge_path_operations()
    |> Enum.into(%{})
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

  defp build_operation(method, path_pattern, requests, routes) do
    route_info = find_route_info(path_pattern, method, routes)

    operation = %{
      "operationId" => generate_operation_id(route_info, method, path_pattern),
      "responses" => build_responses(requests)
    }

    operation
    |> maybe_add_parameters(path_pattern, requests)
    |> maybe_add_request_body(method, requests)
    |> maybe_add_tags(route_info)
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

  defp maybe_add_request_body(operation, method, requests)
       when method in ["POST", "PUT", "PATCH"] do
    body_schemas =
      requests
      |> Enum.map(& &1.body_params)
      |> Enum.reject(&(map_size(&1) == 0))
      |> Enum.map(&TypeInferrer.infer/1)

    case body_schemas do
      [] ->
        operation

      schemas ->
        merged_schema = TypeInferrer.merge_schemas(schemas)

        request_body = %{
          "required" => true,
          "content" => %{
            "application/json" => %{
              "schema" => merged_schema
            }
          }
        }

        Map.put(operation, "requestBody", request_body)
    end
  end

  defp maybe_add_request_body(operation, _method, _requests), do: operation

  # Private functions - Responses

  defp build_responses(requests) do
    requests
    |> Enum.group_by(& &1.response_status)
    |> Enum.map(fn {status, status_requests} ->
      response = build_response(status, status_requests)
      {Integer.to_string(status), response}
    end)
    |> Enum.into(%{})
  end

  defp build_response(status, requests) do
    response = %{
      "description" => status_description(status)
    }

    # Build content schema from response bodies
    body_schemas =
      requests
      |> Enum.map(& &1.response_body)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&TypeInferrer.infer/1)

    case body_schemas do
      [] ->
        response

      schemas ->
        merged_schema = TypeInferrer.merge_schemas(schemas)

        Map.put(response, "content", %{
          "application/json" => %{
            "schema" => merged_schema
          }
        })
    end
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

  defp build_components(_collected_data, config) do
    components = %{}

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
