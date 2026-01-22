defmodule ExUnitOpenAPI.SchemaNamer do
  @moduledoc """
  Generates meaningful schema names from request/response context.

  Names are derived in this order of precedence:
  1. Test tag override (via `@tag openapi: [response_schema: "Name"]`)
  2. Config override (via `schema_names` config)
  3. Inferred from context (controller, action, type)

  ## Naming Convention

  Generated names follow the pattern: `{Action}{Entity}{Type}`

  | Context                | Example Name        |
  |------------------------|---------------------|
  | GET /users/:id 200     | UserShowResponse    |
  | POST /users request    | CreateUserRequest   |
  | GET /users 200         | UserIndexResponse   |
  | 404 response           | NotFoundError       |

  ## Collision Resolution

  When the same name is generated for different schemas:
  - First occurrence: `User`
  - Second occurrence: `User2`
  - Third occurrence: `User3`
  """

  @type context :: %{
          optional(:controller) => module(),
          optional(:action) => atom(),
          optional(:method) => String.t(),
          optional(:path) => String.t(),
          optional(:status) => integer(),
          optional(:type) => :request | :response,
          optional(:openapi_tags) => map()
        }

  @type name_state :: %{
          used_names: MapSet.t(String.t()),
          name_counts: %{String.t() => non_neg_integer()}
        }

  @doc """
  Generates a schema name from context.

  ## Parameters

  - `context` - Map containing controller, action, method, status, type info
  - `config` - ExUnitOpenAPI config (for overrides)
  - `name_state` - State tracking used names for collision resolution

  ## Returns

  `{name, updated_name_state}`
  """
  @spec generate(context(), map(), name_state()) :: {String.t(), name_state()}
  def generate(context, config, name_state) do
    base_name =
      check_tag_override(context) ||
        check_config_override(context, config) ||
        infer_name(context)

    resolve_collision(base_name, name_state)
  end

  @doc """
  Creates a new name state for tracking used names.
  """
  @spec new_state() :: name_state()
  def new_state do
    %{
      used_names: MapSet.new(),
      name_counts: %{}
    }
  end

  @doc """
  Builds a config key for schema name overrides.

  Returns a tuple that can be used as a key in the `schema_names` config.

  ## Examples

      iex> SchemaNamer.config_key(:response, UserController, :show, 200)
      {UserController, :show, :response, 200}

      iex> SchemaNamer.config_key(:request, UserController, :create)
      {UserController, :create, :request}
  """
  @spec config_key(:request | :response, module(), atom(), integer() | nil) :: tuple()
  def config_key(type, controller, action, status \\ nil)

  def config_key(:request, controller, action, _status) do
    {controller, action, :request}
  end

  def config_key(:response, controller, action, status) do
    {controller, action, :response, status}
  end

  # Check for test tag override
  defp check_tag_override(%{openapi_tags: tags, type: type}) when is_map(tags) do
    case type do
      :request -> Map.get(tags, :request_schema)
      :response -> Map.get(tags, :response_schema)
      _ -> nil
    end
  end

  defp check_tag_override(_), do: nil

  # Check for config-based override
  defp check_config_override(context, config) do
    schema_names = Map.get(config, :schema_names, %{})

    key = build_config_key(context)
    Map.get(schema_names, key)
  end

  defp build_config_key(%{controller: controller, action: action, type: :request}) do
    {controller, action, :request}
  end

  defp build_config_key(%{controller: controller, action: action, type: :response, status: status}) do
    {controller, action, :response, status}
  end

  defp build_config_key(%{method: method, path: path, type: :request}) do
    {method, path, :request}
  end

  defp build_config_key(%{method: method, path: path, type: :response, status: status}) do
    {method, path, :response, status}
  end

  defp build_config_key(_), do: nil

  # Infer name from context
  defp infer_name(context) do
    entity = extract_entity(context)
    action = extract_action(context)
    suffix = extract_suffix(context)

    [action, entity, suffix]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("")
    |> ensure_valid_name()
  end

  defp extract_entity(%{controller: controller}) when not is_nil(controller) do
    controller
    |> Module.split()
    |> List.last()
    |> String.replace("Controller", "")
  end

  defp extract_entity(%{path: path}) when is_binary(path) do
    path
    |> String.split("/")
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, ":")))
    |> List.last()
    |> singularize()
    |> camelize()
  end

  defp extract_entity(_), do: "Schema"

  defp extract_action(%{action: action}) when action in [:create, :new] do
    "Create"
  end

  defp extract_action(%{action: action}) when action in [:update, :edit] do
    "Update"
  end

  defp extract_action(%{action: action}) when action in [:delete, :destroy] do
    "Delete"
  end

  defp extract_action(%{action: :index, type: :response}) do
    nil
  end

  defp extract_action(%{action: :show, type: :response}) do
    nil
  end

  defp extract_action(%{method: "POST"}) do
    "Create"
  end

  defp extract_action(%{method: "PUT"}) do
    "Update"
  end

  defp extract_action(%{method: "PATCH"}) do
    "Update"
  end

  defp extract_action(%{method: "DELETE"}) do
    "Delete"
  end

  defp extract_action(_), do: nil

  defp extract_suffix(%{type: :request}) do
    "Request"
  end

  defp extract_suffix(%{type: :response, status: status}) when status in 200..299 do
    "Response"
  end

  defp extract_suffix(%{type: :response, status: 400}) do
    "BadRequestError"
  end

  defp extract_suffix(%{type: :response, status: 401}) do
    "UnauthorizedError"
  end

  defp extract_suffix(%{type: :response, status: 403}) do
    "ForbiddenError"
  end

  defp extract_suffix(%{type: :response, status: 404}) do
    "NotFoundError"
  end

  defp extract_suffix(%{type: :response, status: 422}) do
    "ValidationError"
  end

  defp extract_suffix(%{type: :response, status: status}) when status in 400..499 do
    "Error"
  end

  defp extract_suffix(%{type: :response, status: status}) when status >= 500 do
    "ServerError"
  end

  defp extract_suffix(_), do: nil

  # Resolve naming collisions
  defp resolve_collision(base_name, name_state) do
    if MapSet.member?(name_state.used_names, base_name) do
      count = Map.get(name_state.name_counts, base_name, 1) + 1
      new_name = "#{base_name}#{count}"

      new_state = %{
        name_state
        | used_names: MapSet.put(name_state.used_names, new_name),
          name_counts: Map.put(name_state.name_counts, base_name, count)
      }

      {new_name, new_state}
    else
      new_state = %{
        name_state
        | used_names: MapSet.put(name_state.used_names, base_name)
      }

      {base_name, new_state}
    end
  end

  # Ensure the name is a valid identifier (PascalCase, no special chars)
  defp ensure_valid_name(name) when is_binary(name) do
    name
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> ensure_starts_with_letter()
  end

  defp ensure_valid_name(_), do: "Schema"

  defp ensure_starts_with_letter(""), do: "Schema"

  defp ensure_starts_with_letter(<<first, _rest::binary>> = name) when first in ?A..?Z do
    name
  end

  defp ensure_starts_with_letter(<<first, rest::binary>>) when first in ?a..?z do
    String.upcase(<<first>>) <> rest
  end

  defp ensure_starts_with_letter(_), do: "Schema"

  # Simple singularization (handles common cases)
  defp singularize(nil), do: nil

  defp singularize(word) do
    cond do
      String.ends_with?(word, "ies") ->
        String.replace_suffix(word, "ies", "y")

      String.ends_with?(word, "es") and not String.ends_with?(word, "ses") ->
        String.replace_suffix(word, "es", "")

      String.ends_with?(word, "s") and not String.ends_with?(word, "ss") ->
        String.replace_suffix(word, "s", "")

      true ->
        word
    end
  end

  # Convert to CamelCase
  defp camelize(nil), do: nil

  defp camelize(word) do
    word
    |> String.split(~r/[-_\s]/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end
end
