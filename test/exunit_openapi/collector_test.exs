defmodule ExUnitOpenAPI.CollectorTest do
  use ExUnit.Case

  alias ExUnitOpenAPI.Collector

  setup do
    {:ok, _pid} = Collector.start_link([])
    on_exit(fn -> Collector.clear() end)
    :ok
  end

  describe "capture/1" do
    test "captures request data from conn-like map" do
      conn = %{
        method: "GET",
        request_path: "/api/users/123",
        path_params: %{"id" => "123"},
        query_params: %{"include" => "posts"},
        body_params: %{},
        req_headers: [{"accept", "application/json"}],
        status: 200,
        resp_body: Jason.encode!(%{id: 123, name: "Alice"}),
        resp_headers: [{"content-type", "application/json"}]
      }

      Collector.capture(conn)

      [captured] = Collector.get_collected_data()

      assert captured.method == "GET"
      assert captured.path == "/api/users/123"
      assert captured.path_params == %{"id" => "123"}
      assert captured.query_params == %{"include" => "posts"}
      assert captured.response_status == 200
      assert captured.response_body == %{"id" => 123, "name" => "Alice"}
      assert captured.content_type == "application/json"
    end

    test "parses JSON response body" do
      conn = %{
        method: "GET",
        request_path: "/api/users",
        path_params: %{},
        query_params: %{},
        body_params: %{},
        req_headers: [],
        status: 200,
        resp_body: ~s({"users": [{"id": 1}, {"id": 2}]}),
        resp_headers: [{"content-type", "application/json"}]
      }

      Collector.capture(conn)

      [captured] = Collector.get_collected_data()
      assert captured.response_body == %{"users" => [%{"id" => 1}, %{"id" => 2}]}
    end

    test "handles non-JSON response body" do
      conn = %{
        method: "GET",
        request_path: "/health",
        path_params: %{},
        query_params: %{},
        body_params: %{},
        req_headers: [],
        status: 200,
        resp_body: "OK",
        resp_headers: [{"content-type", "text/plain"}]
      }

      Collector.capture(conn)

      [captured] = Collector.get_collected_data()
      assert captured.response_body == "OK"
    end

    test "handles nil response body" do
      conn = %{
        method: "DELETE",
        request_path: "/api/users/123",
        path_params: %{"id" => "123"},
        query_params: %{},
        body_params: %{},
        req_headers: [],
        status: 204,
        resp_body: nil,
        resp_headers: []
      }

      Collector.capture(conn)

      [captured] = Collector.get_collected_data()
      assert captured.response_body == nil
    end
  end

  describe "get_collected_data/0" do
    test "returns empty list when no data captured" do
      assert Collector.get_collected_data() == []
    end

    test "returns data in order captured" do
      conn1 = %{method: "GET", request_path: "/first", path_params: %{}, query_params: %{}, body_params: %{}, req_headers: [], status: 200, resp_body: nil, resp_headers: []}
      conn2 = %{method: "GET", request_path: "/second", path_params: %{}, query_params: %{}, body_params: %{}, req_headers: [], status: 200, resp_body: nil, resp_headers: []}

      Collector.capture(conn1)
      Collector.capture(conn2)

      data = Collector.get_collected_data()
      assert length(data) == 2
      assert Enum.at(data, 0).path == "/first"
      assert Enum.at(data, 1).path == "/second"
    end
  end

  describe "clear/0" do
    test "removes all collected data" do
      conn = %{method: "GET", request_path: "/test", path_params: %{}, query_params: %{}, body_params: %{}, req_headers: [], status: 200, resp_body: nil, resp_headers: []}

      Collector.capture(conn)
      assert length(Collector.get_collected_data()) == 1

      Collector.clear()
      assert Collector.get_collected_data() == []
    end
  end
end
