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
        merge_with_existing: true          # Preserve manual edits when regenerating
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
    merge_with_existing: true
  }

  @type t :: %{
          router: module() | nil,
          output: String.t(),
          format: :json | :yaml,
          info: map(),
          servers: list(map()),
          security_schemes: map(),
          merge_with_existing: boolean()
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
