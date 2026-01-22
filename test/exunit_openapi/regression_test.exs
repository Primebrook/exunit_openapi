defmodule ExUnitOpenAPI.RegressionTest do
  @moduledoc """
  Regression tests for previously fixed bugs.

  These tests ensure that bugs that were fixed don't reappear.
  """
  use ExUnit.Case, async: true

  alias ExUnitOpenAPI.{Collector, TypeInferrer}

  describe "iolist response body handling (fixed bug)" do
    # Bug: Phoenix returns response bodies as iolists, not plain strings.
    # The collector would fail or return incorrect data when encountering iolists.
    # Fix: Use IO.iodata_to_binary/1 to convert iolists to strings before JSON parsing.

    test "collector handles iolist response body" do
      # Simulate a conn with iolist response body (common in Phoenix)
      iolist_body = ["[", ["{", "\"id\"", ":", "1", "}"], "]"]
      conn = build_conn_with_body(iolist_body)

      # Start collector
      {:ok, _pid} = start_supervised(Collector)

      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      # Should parse the iolist correctly
      assert captured.response_body == [%{"id" => 1}]
    end

    test "collector handles nested iolist" do
      nested_iolist = [["{", [["\"name\"", ":"], ["\"test\""]]], "}"]
      conn = build_conn_with_body(nested_iolist)

      {:ok, _pid} = start_supervised(Collector)

      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      assert captured.response_body == %{"name" => "test"}
    end

    test "collector handles binary response body" do
      binary_body = ~s({"status": "ok"})
      conn = build_conn_with_body(binary_body)

      {:ok, _pid} = start_supervised(Collector)

      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      assert captured.response_body == %{"status" => "ok"}
    end
  end

  describe "unfetched params handling (fixed bug)" do
    # Bug: Plug.Conn params could be Plug.Conn.Unfetched structs when not
    # explicitly fetched. The collector would crash or return incorrect data.
    # Fix: Check for struct types and return empty map for unfetched params.

    test "collector handles unfetched path_params" do
      conn = %{
        method: "GET",
        request_path: "/api/test",
        path_params: %Plug.Conn.Unfetched{aspect: :path_params},
        query_params: %{},
        body_params: %{},
        req_headers: [],
        resp_headers: [],
        status: 200,
        resp_body: "{}"
      }

      {:ok, _pid} = start_supervised(Collector)

      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      # Should return empty map for unfetched params
      assert captured.path_params == %{}
    end

    test "collector handles unfetched query_params" do
      conn = %{
        method: "GET",
        request_path: "/api/test",
        path_params: %{},
        query_params: %Plug.Conn.Unfetched{aspect: :query_params},
        body_params: %{},
        req_headers: [],
        resp_headers: [],
        status: 200,
        resp_body: "{}"
      }

      {:ok, _pid} = start_supervised(Collector)

      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      assert captured.query_params == %{}
    end

    test "collector handles unfetched body_params" do
      conn = %{
        method: "POST",
        request_path: "/api/test",
        path_params: %{},
        query_params: %{},
        body_params: %Plug.Conn.Unfetched{aspect: :body_params},
        req_headers: [],
        resp_headers: [],
        status: 201,
        resp_body: "{}"
      }

      {:ok, _pid} = start_supervised(Collector)

      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      assert captured.body_params == %{}
    end

    test "collector handles mixed fetched and unfetched params" do
      conn = %{
        method: "GET",
        request_path: "/api/users/123",
        path_params: %{"id" => "123"},
        query_params: %Plug.Conn.Unfetched{aspect: :query_params},
        body_params: %Plug.Conn.Unfetched{aspect: :body_params},
        req_headers: [],
        resp_headers: [],
        status: 200,
        resp_body: ~s({"id": 123})
      }

      {:ok, _pid} = start_supervised(Collector)

      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      assert captured.path_params == %{"id" => "123"}
      assert captured.query_params == %{}
      assert captured.body_params == %{}
    end
  end

  describe "conn struct pattern matching (fixed bug)" do
    # Bug: Original code used %Plug.Conn{} pattern match, but Plug is a test-only
    # dependency. This caused compilation errors.
    # Fix: Use %{method: _, request_path: _} duck-typing instead.

    test "collector accepts map with conn-like fields" do
      # Plain map, not a Plug.Conn struct
      conn = %{
        method: "GET",
        request_path: "/test",
        path_params: %{},
        query_params: %{},
        body_params: %{},
        req_headers: [],
        resp_headers: [],
        status: 200,
        resp_body: ~s({"ok": true})
      }

      {:ok, _pid} = start_supervised(Collector)

      # Should not crash - accepts any map with required fields
      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      assert captured.method == "GET"
      assert captured.path == "/test"
    end
  end

  describe "integer array vs charlist detection (fixed bug)" do
    # Bug: Initial implementation tried to detect charlists (lists of small integers)
    # to handle them specially. This broke legitimate integer arrays.
    # Fix: Removed charlist detection since iolist handling made it unnecessary.

    test "type inferrer correctly handles integer arrays" do
      schema = TypeInferrer.infer([1, 2, 3, 4, 5])

      assert schema["type"] == "array"
      assert schema["items"]["type"] == "integer"
    end

    test "type inferrer handles arrays with small integers (potential charlist confusion)" do
      # These small integers could be mistaken for a charlist
      schema = TypeInferrer.infer([65, 66, 67])

      assert schema["type"] == "array"
      assert schema["items"]["type"] == "integer"
    end

    test "type inferrer handles mixed integer arrays" do
      schema = TypeInferrer.infer([1, 100, 1000, 10000])

      assert schema["type"] == "array"
      assert schema["items"]["type"] == "integer"
    end
  end

  describe "empty and null response handling" do
    test "collector handles nil response body" do
      conn = build_conn_with_body(nil)

      {:ok, _pid} = start_supervised(Collector)

      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      assert captured.response_body == nil
    end

    test "collector handles empty string response body" do
      conn = build_conn_with_body("")

      {:ok, _pid} = start_supervised(Collector)

      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      assert captured.response_body == nil
    end

    test "collector handles null JSON response" do
      conn = build_conn_with_body("null")

      {:ok, _pid} = start_supervised(Collector)

      Collector.capture(conn)
      [captured] = Collector.get_collected_data()

      assert captured.response_body == nil
    end
  end

  # Helper functions

  defp build_conn_with_body(body) do
    %{
      method: "GET",
      request_path: "/api/test",
      path_params: %{},
      query_params: %{},
      body_params: %{},
      req_headers: [],
      resp_headers: [{"content-type", "application/json"}],
      status: 200,
      resp_body: body
    }
  end
end
