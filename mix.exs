defmodule ExUnitOpenAPI.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/primebrook/exunit_openapi"

  def project do
    [
      app: :exunit_openapi,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "ExUnitOpenAPI",
      source_url: @source_url
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {ExUnitOpenAPI.Application, []}
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.9", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:phoenix, "~> 1.7", only: :test},
      {:plug, "~> 1.14", only: :test}
    ]
  end

  defp description do
    """
    Automatically generate OpenAPI specifications from your ExUnit controller tests.
    Zero annotations required - just run your tests and get documentation.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
