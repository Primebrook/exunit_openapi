# Suppress noisy logs during tests
Logger.configure(level: :warning)

# Configure the test endpoint
Application.put_env(:exunit_openapi, ExUnitOpenAPI.TestApp.Endpoint,
  http: [port: 4002],
  server: false,
  secret_key_base: String.duplicate("a", 64)
)

# Start the test endpoint
{:ok, _} = ExUnitOpenAPI.TestApp.Endpoint.start_link()

ExUnit.start()
