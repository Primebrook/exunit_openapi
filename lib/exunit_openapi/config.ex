defmodule ExUnitOpenAPI.Config do
  @moduledoc """
  Configuration management for ExUnitOpenAPI.

  ## Configuration Options

      config :exunit_openapi,
        router: MyAppWeb.Router,           # Required: Your Phoenix router module
        output: "openapi.json",            # Output file path (default: openapi.json)
        format: :json,                     # Output format: :json or :yaml
        info: [                            # OpenAPI info object
          title: "My API",
          version: "1.0.0",
          description: "API description"
        ],
        servers: [                         # Optional: Server URLs
          %{url: "https://api.example.com", description: "Production"}
        ],
        security_schemes: %{},             # Optional: Security scheme definitions
        merge_with_existing: true,         # Preserve manual edits when regenerating

        # Schema Deduplication Options
        schema_deduplication: true,        # Enable $ref deduplication (default: true)
        schema_names: %{},                 # Override inferred schema names
        extract_single_use: false,         # Extract schemas used only once (default: false)
        min_properties_for_extraction: 3,  # Min properties to extract nested objects

        # Enum Inference Options
        enum_inference: true,              # Auto-detect enums from samples (default: true)
        enum_min_samples: 3,               # Min samples needed to infer enum
        enum_max_values: 10                # Max unique values to be considered enum

  ## Schema Name Overrides

  Use the `schema_names` option to override inferred names:

      config :exunit_openapi,
        schema_names: %{
          # By controller/action
          {MyApp.UserController, :show, :response, 200} => "UserDetails",
          {MyApp.UserController, :create, :request} => "NewUser",

          # By path pattern
          {"GET", "/users/:id", :response, 200} => "UserProfile"
        }

  Or use test tags for per-test overrides:

      @tag openapi: [response_schema: "CustomName"]
      test "my test", %{conn: conn} do
        # ...
      end
  """

  @default_config %{
    router: nil,
    output: "openapi.json",
    format: :json,
    info: %{
      title: "API",
      version: "1.0.0"
    },
    servers: [],
    security_schemes: %{},
    merge_with_existing: true,
    # Schema deduplication options
    schema_deduplication: true,
    schema_names: %{},
    extract_single_use: false,
    min_properties_for_extraction: 3,
    # Enum inference options
    enum_inference: true,
    enum_min_samples: 3,
    enum_max_values: 10
  }

  @type t :: %{
          router: module() | nil,
          output: String.t(),
          format: :json | :yaml,
          info: map(),
          servers: list(map()),
          security_schemes: map(),
          merge_with_existing: boolean(),
          schema_deduplication: boolean(),
          schema_names: map(),
          extract_single_use: boolean(),
          min_properties_for_extraction: pos_integer(),
          enum_inference: boolean(),
          enum_min_samples: pos_integer(),
          enum_max_values: pos_integer()
        }

  @doc """
  Loads configuration from application env and optional overrides.
  """
  @spec load(keyword()) :: t()
  def load(opts \\ []) do
    app_config =
      Application.get_all_env(:exunit_openapi)
      |> Enum.into(%{})

    @default_config
    |> Map.merge(app_config)
    |> Map.merge(normalize_opts(opts))
    |> normalize_info()
  end

  @doc """
  Gets the output file path from config.
  """
  @spec output_path(t()) :: String.t()
  def output_path(%{output: output}), do: output

  @doc """
  Gets the output format from config.
  """
  @spec format(t()) :: :json | :yaml
  def format(%{format: format}), do: format

  @doc """
  Gets the router module from config.
  """
  @spec router(t()) :: module() | nil
  def router(%{router: router}), do: router

  @doc """
  Gets the info section from config.
  """
  @spec info(t()) :: map()
  def info(%{info: info}), do: info

  @doc """
  Gets the servers list from config.
  """
  @spec servers(t()) :: list(map())
  def servers(%{servers: servers}), do: servers

  @doc """
  Gets the security schemes from config.
  """
  @spec security_schemes(t()) :: map()
  def security_schemes(%{security_schemes: schemes}), do: schemes

  @doc """
  Returns whether to merge with existing spec file.
  """
  @spec merge_with_existing?(t()) :: boolean()
  def merge_with_existing?(%{merge_with_existing: merge}), do: merge

  @doc """
  Returns whether schema deduplication is enabled.
  """
  @spec schema_deduplication?(t()) :: boolean()
  def schema_deduplication?(%{schema_deduplication: enabled}), do: enabled

  @doc """
  Gets the schema name overrides map.
  """
  @spec schema_names(t()) :: map()
  def schema_names(%{schema_names: names}), do: names

  @doc """
  Returns whether to extract single-use schemas.
  """
  @spec extract_single_use?(t()) :: boolean()
  def extract_single_use?(%{extract_single_use: extract}), do: extract

  @doc """
  Gets the minimum properties threshold for extraction.
  """
  @spec min_properties_for_extraction(t()) :: pos_integer()
  def min_properties_for_extraction(%{min_properties_for_extraction: min}), do: min

  @doc """
  Returns whether enum inference is enabled.
  """
  @spec enum_inference?(t()) :: boolean()
  def enum_inference?(%{enum_inference: enabled}), do: enabled

  @doc """
  Gets the minimum samples needed for enum inference.
  """
  @spec enum_min_samples(t()) :: pos_integer()
  def enum_min_samples(%{enum_min_samples: min}), do: min

  @doc """
  Gets the maximum unique values for enum inference.
  """
  @spec enum_max_values(t()) :: pos_integer()
  def enum_max_values(%{enum_max_values: max}), do: max

  # Private functions

  defp normalize_opts(opts) do
    opts
    |> Enum.into(%{})
  end

  defp normalize_info(%{info: info} = config) when is_list(info) do
    %{config | info: Enum.into(info, %{})}
  end

  defp normalize_info(config), do: config
end
