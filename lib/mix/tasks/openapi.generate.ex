defmodule Mix.Tasks.Openapi.Generate do
  @shortdoc "Runs tests and generates OpenAPI specification"

  @moduledoc """
  Runs the test suite with OpenAPI collection enabled and generates the spec.

      $ mix openapi.generate

  This is equivalent to running:

      $ OPENAPI=1 mix test

  ## Options

    * `--output` - Output file path (default: from config or "openapi.json")
    * `--format` - Output format: json or yaml (default: json)
    * `--only` - Only run tests matching the given tag
    * `--exclude` - Exclude tests matching the given tag

  ## Examples

      $ mix openapi.generate
      $ mix openapi.generate --output priv/static/openapi.json
      $ mix openapi.generate --only integration

  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          output: :string,
          format: :string,
          only: :keep,
          exclude: :keep
        ]
      )

    # Set the OPENAPI env var to enable collection
    System.put_env("OPENAPI", "1")

    # Pass through test options
    test_args =
      opts
      |> Enum.flat_map(fn
        {:only, tag} -> ["--only", tag]
        {:exclude, tag} -> ["--exclude", tag]
        _ -> []
      end)

    # Store custom options for the generator
    if opts[:output] do
      Application.put_env(:exunit_openapi, :output, opts[:output])
    end

    if opts[:format] do
      format = String.to_atom(opts[:format])
      Application.put_env(:exunit_openapi, :format, format)
    end

    # Run the test task
    Mix.Task.run("test", test_args)
  end
end
