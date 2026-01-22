defmodule ExUnitOpenAPI.Collector do
  @moduledoc """
  GenServer that collects HTTP request/response data from Phoenix tests.

  The Collector captures `Plug.Conn` structs from telemetry events and stores
  them for later processing into an OpenAPI specification.

  ## Collected Data Structure

  Each captured request is stored as:

      %{
        method: "GET",
        path: "/api/users/123",
        path_params: %{"id" => "123"},
        query_params: %{},
        body_params: %{},
        request_headers: [...],
        response_status: 200,
        response_body: %{...},
        response_headers: [...],
        content_type: "application/json"
      }

  Requests are grouped by `{method, path_pattern}` to aggregate multiple
  examples of the same endpoint.
  """

  use GenServer

  require Logger

  @type request_data :: %{
          method: String.t(),
          path: String.t(),
          path_params: map(),
          query_params: map(),
          body_params: map(),
          request_headers: list({String.t(), String.t()}),
          response_status: non_neg_integer(),
          response_body: term(),
          response_headers: list({String.t(), String.t()}),
          content_type: String.t() | nil
        }

  # Client API

  @doc """
  Starts the Collector GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Captures request/response data from a Plug.Conn.
  """
  @spec capture(Plug.Conn.t()) :: :ok
  def capture(%Plug.Conn{} = conn) do
    GenServer.cast(__MODULE__, {:capture, conn})
  end

  @doc """
  Returns all collected request data.
  """
  @spec get_collected_data() :: list(request_data())
  def get_collected_data do
    GenServer.call(__MODULE__, :get_data)
  end

  @doc """
  Clears all collected data.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{requests: []}}
  end

  @impl true
  def handle_cast({:capture, conn}, state) do
    request_data = extract_request_data(conn)
    {:noreply, %{state | requests: [request_data | state.requests]}}
  end

  @impl true
  def handle_cast(:clear, _state) do
    {:noreply, %{requests: []}}
  end

  @impl true
  def handle_call(:get_data, _from, state) do
    {:reply, Enum.reverse(state.requests), state}
  end

  # Private functions

  defp extract_request_data(conn) do
    %{
      method: conn.method,
      path: conn.request_path,
      path_params: conn.path_params || %{},
      query_params: conn.query_params || %{},
      body_params: extract_body_params(conn),
      request_headers: conn.req_headers,
      response_status: conn.status,
      response_body: parse_response_body(conn),
      response_headers: conn.resp_headers,
      content_type: get_content_type(conn)
    }
  end

  defp extract_body_params(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} -> %{}
      params when is_map(params) -> params
      _ -> %{}
    end
  end

  defp parse_response_body(conn) do
    case conn.resp_body do
      nil ->
        nil

      "" ->
        nil

      body when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, decoded} -> decoded
          {:error, _} -> body
        end

      body ->
        body
    end
  end

  defp get_content_type(conn) do
    conn.resp_headers
    |> Enum.find(fn {key, _value} -> String.downcase(key) == "content-type" end)
    |> case do
      {_, value} -> value
      nil -> nil
    end
  end
end
