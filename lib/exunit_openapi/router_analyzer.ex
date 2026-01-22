defmodule ExUnitOpenAPI.RouterAnalyzer do
  @moduledoc """
  Analyzes Phoenix routers to extract route patterns and metadata.

  This module parses the compiled route information from a Phoenix router
  to match captured requests to their route definitions, extracting:

  - Path patterns with parameter placeholders (e.g., `/users/:id`)
  - HTTP methods
  - Controller and action names
  - Pipe names (for grouping/tagging)
  """

  @type route_info :: %{
          path: String.t(),
          method: String.t(),
          controller: module(),
          action: atom(),
          pipe_through: list(atom())
        }

  @doc """
  Analyzes a Phoenix router module and returns route information.

  ## Example

      iex> RouterAnalyzer.analyze(MyAppWeb.Router)
      [
        %{path: "/api/users", method: "GET", controller: UserController, action: :index, ...},
        %{path: "/api/users/:id", method: "GET", controller: UserController, action: :show, ...}
      ]
  """
  @spec analyze(module()) :: list(route_info())
  def analyze(router) when is_atom(router) do
    if function_exported?(router, :__routes__, 0) do
      router.__routes__()
      |> Enum.map(&extract_route_info/1)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  @doc """
  Matches a request path to a route pattern.

  Returns the matching route info with extracted path parameters.

  ## Example

      iex> RouterAnalyzer.match_route("/api/users/123", routes)
      {:ok, %{path: "/api/users/:id", ...}, %{"id" => "123"}}
  """
  @spec match_route(String.t(), String.t(), list(route_info())) ::
          {:ok, route_info(), map()} | :no_match
  def match_route(request_path, method, routes) do
    routes
    |> Enum.filter(&(&1.method == method))
    |> Enum.find_value(fn route ->
      case match_path_pattern(route.path, request_path) do
        {:ok, params} -> {:ok, route, params}
        :no_match -> nil
      end
    end)
    |> case do
      nil -> :no_match
      result -> result
    end
  end

  @doc """
  Converts a route path to an OpenAPI path format.

  Phoenix uses `:param` syntax, OpenAPI uses `{param}`.

  ## Example

      iex> RouterAnalyzer.to_openapi_path("/users/:id/posts/:post_id")
      "/users/{id}/posts/{post_id}"
  """
  @spec to_openapi_path(String.t()) :: String.t()
  def to_openapi_path(phoenix_path) do
    phoenix_path
    |> String.split("/")
    |> Enum.map(fn
      ":" <> param -> "{#{param}}"
      "*" <> param -> "{#{param}}"
      segment -> segment
    end)
    |> Enum.join("/")
  end

  @doc """
  Extracts path parameter names from a route path.

  ## Example

      iex> RouterAnalyzer.extract_path_params("/users/:id/posts/:post_id")
      ["id", "post_id"]
  """
  @spec extract_path_params(String.t()) :: list(String.t())
  def extract_path_params(path) do
    path
    |> String.split("/")
    |> Enum.filter(&String.starts_with?(&1, ":"))
    |> Enum.map(&String.trim_leading(&1, ":"))
  end

  # Private functions

  defp extract_route_info(%{path: path, plug: controller, plug_opts: action, verb: verb} = route) do
    %{
      path: path,
      method: verb_to_method(verb),
      controller: controller,
      action: action,
      pipe_through: Map.get(route, :pipe_through, [])
    }
  end

  defp extract_route_info(_), do: nil

  defp verb_to_method(verb) when is_atom(verb) do
    verb
    |> Atom.to_string()
    |> String.upcase()
  end

  defp match_path_pattern(pattern, path) do
    pattern_segments = String.split(pattern, "/")
    path_segments = String.split(path, "/")

    if length(pattern_segments) == length(path_segments) do
      match_segments(pattern_segments, path_segments, %{})
    else
      :no_match
    end
  end

  defp match_segments([], [], params), do: {:ok, params}

  defp match_segments([":" <> param | pattern_rest], [value | path_rest], params) do
    match_segments(pattern_rest, path_rest, Map.put(params, param, value))
  end

  defp match_segments(["*" <> param | _pattern_rest], path_rest, params) do
    # Catch-all parameter - captures the rest of the path
    {:ok, Map.put(params, param, Enum.join(path_rest, "/"))}
  end

  defp match_segments([segment | pattern_rest], [segment | path_rest], params) do
    # Literal segment match
    match_segments(pattern_rest, path_rest, params)
  end

  defp match_segments(_, _, _), do: :no_match
end
