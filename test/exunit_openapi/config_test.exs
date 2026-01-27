defmodule ExUnitOpenAPI.ConfigTest do
  use ExUnit.Case, async: false

  alias ExUnitOpenAPI.Config

  setup do
    # Save original env
    original_env = Application.get_all_env(:exunit_openapi)

    on_exit(fn ->
      # Clear all env
      Application.get_all_env(:exunit_openapi)
      |> Keyword.keys()
      |> Enum.each(&Application.delete_env(:exunit_openapi, &1))

      # Restore original env
      Enum.each(original_env, fn {key, value} ->
        Application.put_env(:exunit_openapi, key, value)
      end)
    end)

    # Clear env before each test
    Application.get_all_env(:exunit_openapi)
    |> Keyword.keys()
    |> Enum.each(&Application.delete_env(:exunit_openapi, &1))

    :ok
  end

  describe "load/1" do
    test "returns default config when no config is set" do
      config = Config.load()

      assert config.router == nil
      assert config.output == "openapi.json"
      assert config.info == %{title: "API", version: "1.0.0"}
      assert config.servers == []
      assert config.security_schemes == %{}
      assert config.merge_with_existing == true
    end

    test "loads config from application env" do
      Application.put_env(:exunit_openapi, :router, MyApp.Router)
      Application.put_env(:exunit_openapi, :output, "priv/api.json")

      config = Config.load()

      assert config.router == MyApp.Router
      assert config.output == "priv/api.json"
    end

    test "override options take precedence over app env" do
      Application.put_env(:exunit_openapi, :router, MyApp.Router)
      Application.put_env(:exunit_openapi, :output, "priv/api.json")

      config = Config.load(router: OtherApp.Router, output: "custom.json")

      assert config.router == OtherApp.Router
      assert config.output == "custom.json"
    end

    test "normalizes info from keyword list to map" do
      Application.put_env(:exunit_openapi, :info, title: "My API", version: "2.0.0")

      config = Config.load()

      assert config.info == %{title: "My API", version: "2.0.0"}
    end

    test "handles info as map" do
      Application.put_env(:exunit_openapi, :info, %{title: "My API", version: "3.0.0"})

      config = Config.load()

      assert config.info == %{title: "My API", version: "3.0.0"}
    end

    test "loads servers configuration" do
      servers = [
        %{url: "https://api.example.com", description: "Production"},
        %{url: "https://staging.example.com", description: "Staging"}
      ]

      Application.put_env(:exunit_openapi, :servers, servers)

      config = Config.load()

      assert config.servers == servers
    end

    test "loads security schemes configuration" do
      security_schemes = %{
        "bearerAuth" => %{
          "type" => "http",
          "scheme" => "bearer"
        }
      }

      Application.put_env(:exunit_openapi, :security_schemes, security_schemes)

      config = Config.load()

      assert config.security_schemes == security_schemes
    end

    test "loads merge_with_existing configuration" do
      Application.put_env(:exunit_openapi, :merge_with_existing, false)

      config = Config.load()

      assert config.merge_with_existing == false
    end
  end

  describe "accessor functions" do
    test "output_path/1 returns output path" do
      config = Config.load(output: "custom/path.json")
      assert Config.output_path(config) == "custom/path.json"
    end

    test "router/1 returns router module" do
      config = Config.load(router: MyApp.Router)
      assert Config.router(config) == MyApp.Router
    end

    test "info/1 returns info map" do
      Application.put_env(:exunit_openapi, :info, title: "Test API", version: "1.0.0")
      config = Config.load()
      assert Config.info(config) == %{title: "Test API", version: "1.0.0"}
    end

    test "servers/1 returns servers list" do
      servers = [%{url: "https://api.example.com"}]
      config = Config.load(servers: servers)
      assert Config.servers(config) == servers
    end

    test "security_schemes/1 returns security schemes" do
      schemes = %{"apiKey" => %{"type" => "apiKey"}}
      config = Config.load(security_schemes: schemes)
      assert Config.security_schemes(config) == schemes
    end

    test "merge_with_existing?/1 returns boolean" do
      config = Config.load(merge_with_existing: false)
      assert Config.merge_with_existing?(config) == false

      config = Config.load(merge_with_existing: true)
      assert Config.merge_with_existing?(config) == true
    end
  end

  describe "edge cases" do
    test "handles empty info keyword list" do
      Application.put_env(:exunit_openapi, :info, [])
      config = Config.load()
      assert config.info == %{}
    end

    test "handles nil values in opts" do
      config = Config.load(router: nil, output: nil)
      assert config.router == nil
      assert config.output == nil
    end

    test "preserves unknown keys from app env" do
      Application.put_env(:exunit_openapi, :custom_option, "custom_value")
      config = Config.load()
      assert config[:custom_option] == "custom_value"
    end
  end
end
