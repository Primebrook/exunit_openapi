defmodule ExUnitOpenAPI.Integration.TelemetryTest do
  @moduledoc """
  Tests for telemetry integration:
  - Handler attachment/detachment
  - Event filtering
  - Error handling when Collector is unavailable
  """
  use ExUnitOpenAPI.ConnCase, async: false

  alias ExUnitOpenAPI.Collector

  @handler_id "exunit-openapi-collector"

  setup do
    # Clean up any existing state
    :telemetry.detach(@handler_id)
    if Process.whereis(Collector), do: GenServer.stop(Collector)

    on_exit(fn ->
      :telemetry.detach(@handler_id)
      if Process.whereis(Collector), do: GenServer.stop(Collector)
    end)

    :ok
  end

  describe "ExUnitOpenAPI.start/1" do
    test "attaches telemetry handler when OPENAPI env is set" do
      System.put_env("OPENAPI", "1")

      try do
        ExUnitOpenAPI.start()

        # Verify handler is attached
        handlers = :telemetry.list_handlers([:phoenix, :router_dispatch, :stop])
        handler_ids = Enum.map(handlers, & &1.id)
        assert @handler_id in handler_ids
      after
        System.delete_env("OPENAPI")
      end
    end

    test "does not attach handler when OPENAPI env is not set" do
      System.delete_env("OPENAPI")

      ExUnitOpenAPI.start()

      # Handler should not be attached
      handlers = :telemetry.list_handlers([:phoenix, :router_dispatch, :stop])
      handler_ids = Enum.map(handlers, & &1.id)
      refute @handler_id in handler_ids
    end

    test "starts collector when OPENAPI env is set" do
      System.put_env("OPENAPI", "1")

      try do
        refute Process.whereis(Collector)
        ExUnitOpenAPI.start()
        assert Process.whereis(Collector)
      after
        System.delete_env("OPENAPI")
      end
    end
  end

  describe "telemetry event handling" do
    setup do
      {:ok, _} = Collector.start_link([])

      # Manually attach handler for testing
      :telemetry.attach(
        @handler_id,
        [:phoenix, :router_dispatch, :stop],
        &ExUnitOpenAPI.Integration.TelemetryTest.test_handler/4,
        nil
      )

      :ok
    end

    test "captures request data from telemetry event", %{conn: conn} do
      # Make a request - this will trigger telemetry
      _conn = get(conn, "/api/users/1")

      # Verify data was captured
      collected = Collector.get_collected_data()
      assert length(collected) == 1

      [captured] = collected
      assert captured.method == "GET"
      assert captured.path == "/api/users/1"
      assert captured.response_status == 200
    end

    test "captures multiple requests", %{conn: conn} do
      _conn1 = get(conn, "/api/users/1")
      _conn2 = get(conn, "/api/users/2")
      _conn3 = post(conn, "/api/users", %{user: %{name: "Test"}})

      collected = Collector.get_collected_data()
      assert length(collected) == 3
    end

    test "captures POST request body", %{conn: conn} do
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/users", %{user: %{name: "Alice", email: "alice@test.com"}})

      [captured] = Collector.get_collected_data()
      assert captured.method == "POST"
      assert captured.body_params["user"]["name"] == "Alice"
    end

    test "captures response body", %{conn: conn} do
      _conn = get(conn, "/api/users/1")

      [captured] = Collector.get_collected_data()
      assert captured.response_body["id"] == 1
      assert captured.response_body["name"] == "Test User"
    end

    test "captures query parameters", %{conn: conn} do
      _conn = get(conn, "/api/users", page: "2", per_page: "25")

      [captured] = Collector.get_collected_data()
      assert captured.query_params["page"] == "2"
      assert captured.query_params["per_page"] == "25"
    end
  end

  describe "error resilience" do
    test "handles request when collector is not running", %{conn: conn} do
      # Ensure collector is not running
      if Process.whereis(Collector), do: GenServer.stop(Collector)
      refute Process.whereis(Collector)

      # Attach handler that would try to use collector
      :telemetry.attach(
        @handler_id,
        [:phoenix, :router_dispatch, :stop],
        &__MODULE__.resilient_handler/4,
        nil
      )

      # Request should still complete without error
      conn = get(conn, "/api/users/1")
      assert conn.status == 200
    end
  end

  # Test handler function (using module function to avoid performance warning)
  def test_handler(_event, _measurements, metadata, _config) do
    case metadata do
      %{conn: conn} -> Collector.capture(conn)
      _ -> :ok
    end
  end

  # Resilient handler that doesn't crash when collector is down
  def resilient_handler(_event, _measurements, metadata, _config) do
    case metadata do
      %{conn: conn} ->
        try do
          Collector.capture(conn)
        catch
          :exit, _ -> :ok
        end

      _ ->
        :ok
    end
  end
end
