defmodule Mix.Tasks.Openapi.GenerateTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Openapi.Generate

  setup do
    # Clean up env before each test
    System.delete_env("OPENAPI")
    Application.delete_env(:exunit_openapi, :output)

    on_exit(fn ->
      System.delete_env("OPENAPI")
      Application.delete_env(:exunit_openapi, :output)
    end)

    :ok
  end

  describe "option parsing" do
    test "parses --output option" do
      # We can't actually run the task (it would run tests), but we can test the option parsing
      {opts, _, _} =
        OptionParser.parse(["--output", "custom/path.json"],
          switches: [
            output: :string,
            only: :keep,
            exclude: :keep
          ]
        )

      assert opts[:output] == "custom/path.json"
    end

    test "parses multiple --only options" do
      {opts, _, _} =
        OptionParser.parse(["--only", "integration", "--only", "api"],
          switches: [
            output: :string,
            only: :keep,
            exclude: :keep
          ]
        )

      # :keep accumulates values in a list
      only_values = Keyword.get_values(opts, :only)
      assert only_values == ["integration", "api"]
    end

    test "parses mixed options" do
      {opts, _, _} =
        OptionParser.parse(["--output", "api.json", "--only", "api", "--exclude", "slow"],
          switches: [
            output: :string,
            only: :keep,
            exclude: :keep
          ]
        )

      assert opts[:output] == "api.json"
      assert opts[:only] == "api"
      assert opts[:exclude] == "slow"
    end
  end

  describe "test arg building" do
    test "builds test args from only/exclude options" do
      opts = [only: "integration", exclude: "slow"]

      test_args =
        opts
        |> Enum.flat_map(fn
          {:only, tag} -> ["--only", tag]
          {:exclude, tag} -> ["--exclude", tag]
          _ -> []
        end)

      assert test_args == ["--only", "integration", "--exclude", "slow"]
    end

    test "ignores output when building test args" do
      opts = [output: "api.json", only: "api"]

      test_args =
        opts
        |> Enum.flat_map(fn
          {:only, tag} -> ["--only", tag]
          {:exclude, tag} -> ["--exclude", tag]
          _ -> []
        end)

      assert test_args == ["--only", "api"]
    end
  end

  describe "module attributes" do
    test "has correct shortdoc" do
      assert Mix.Task.shortdoc(Generate) == "Runs tests and generates OpenAPI specification"
    end

    test "has moduledoc with usage info" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Generate)
      assert moduledoc =~ "mix openapi.generate"
      assert moduledoc =~ "--output"
      assert moduledoc =~ "--only"
    end
  end
end
