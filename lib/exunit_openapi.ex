defmodule ExUnitOpenAPI do
  @moduledoc """
  Automatically generate OpenAPI specifications from your ExUnit controller tests.

  ## Quick Start

  1. Add to your `test/test_helper.exs`:

      ExUnitOpenAPI.start()
      ExUnit.start()

  2. Configure in `config/test.exs`:

      config :exunit_openapi,
        router: MyAppWeb.Router,
        output: "priv/static/openapi.json",
        info: [
          title: "My API",
          version: "1.0.0"
        ]

  3. Run tests with OpenAPI generation:

      OPENAPI=1 mix test

  ## How It Works

  ExUnitOpenAPI attaches to Phoenix telemetry events during test runs. When your
  controller tests make requests via `Phoenix.ConnTest`, the library captures:

  - Request method, path, and parameters
  - Response status and JSON body
  - Route patterns from your Phoenix router

  After tests complete, it generates an OpenAPI 3.0 specification with:

  - Paths and operations inferred from captured requests
  - Schemas inferred from JSON response bodies
  - Parameters extracted from route patterns and request data
  """

  alias ExUnitOpenAPI.{Collector, Generator, Config}

  @doc """
  Starts the OpenAPI collector.

  Call this in your `test/test_helper.exs` before `ExUnit.start()`:

      ExUnitOpenAPI.start()
      ExUnit.start()

  The collector only activates when the `OPENAPI` environment variable is set:

      OPENAPI=1 mix test
  """
  @spec start(keyword()) :: :ok | {:error, term()}
  def start(opts \\ []) do
    if enabled?() do
      {:ok, _pid} = Collector.start_link(opts)
      attach_telemetry()
      setup_exit_hook()
      :ok
    else
      :ok
    end
  end

  @doc """
  Returns whether OpenAPI generation is enabled.

  Generation is enabled when the `OPENAPI` environment variable is set to any value.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    System.get_env("OPENAPI") != nil
  end

  @doc """
  Manually triggers OpenAPI spec generation.

  This is called automatically when tests complete if `OPENAPI=1` is set.
  You can also call it manually if needed.
  """
  @spec generate(keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(opts \\ []) do
    config = Config.load(opts)
    collected_data = Collector.get_collected_data()

    case Generator.generate(collected_data, config) do
      {:ok, spec} ->
        output_path = Config.output_path(config)
        write_spec(spec, output_path, config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Applies OpenAPI tags from test context to a connection.

  Use this in your ConnCase setup to enable per-test schema name overrides:

      # In test/support/conn_case.ex
      setup context do
        conn = Phoenix.ConnTest.build_conn()
        conn = ExUnitOpenAPI.apply_openapi_tags(conn, context)
        {:ok, conn: conn}
      end

  Then in your tests:

      @tag openapi: [response_schema: "CustomUserSchema"]
      test "shows user", %{conn: conn} do
        conn = get(conn, "/users/123")
        # Response schema will be named "CustomUserSchema"
      end

  ## Supported Tags

  - `:response_schema` - Override the response schema name
  - `:request_schema` - Override the request body schema name
  """
  @spec apply_openapi_tags(map(), map()) :: map()
  defdelegate apply_openapi_tags(conn, context), to: Collector

  # Private functions

  defp attach_telemetry do
    :telemetry.attach(
      "exunit-openapi-collector",
      [:phoenix, :router_dispatch, :stop],
      &handle_telemetry_event/4,
      nil
    )
  end

  defp handle_telemetry_event(_event, _measurements, metadata, _config) do
    case metadata do
      %{conn: conn} ->
        Collector.capture(conn)

      _ ->
        :ok
    end
  end

  defp setup_exit_hook do
    System.at_exit(fn _status ->
      if enabled?() do
        case generate() do
          {:ok, path} ->
            IO.puts("\n#{IO.ANSI.green()}OpenAPI spec generated: #{path}#{IO.ANSI.reset()}")

          {:error, reason} ->
            IO.puts("\n#{IO.ANSI.red()}Failed to generate OpenAPI spec: #{inspect(reason)}#{IO.ANSI.reset()}")
        end
      end
    end)
  end

  defp write_spec(spec, output_path, config) do
    dir = Path.dirname(output_path)
    File.mkdir_p!(dir)

    content =
      case Config.format(config) do
        :json -> Jason.encode!(spec, pretty: true)
        :yaml -> encode_yaml(spec)
      end

    File.write!(output_path, content)
    {:ok, output_path}
  end

  defp encode_yaml(spec) do
    if Code.ensure_loaded?(YamlElixir) do
      # YamlElixir doesn't have an encoder, so we'd need a different library
      # For now, fall back to JSON
      Jason.encode!(spec, pretty: true)
    else
      raise "yaml_elixir is required for YAML output. Add {:yaml_elixir, \"~> 2.9\"} to your deps."
    end
  end
end
