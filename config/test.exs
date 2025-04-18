import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :redactly, Redactly.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "redactly_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :redactly, RedactlyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "h6DZEIBwdSon3OxG27186z8e86wj0Ujd/aJENo56DecZKz9xuGh9lHQ2nnryePnY",
  server: false

# In test we don't send emails
config :redactly, Redactly.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :redactly,
  slack_req_options: [
    plug: {Req.Test, Redactly.Integrations.Slack},
    retry: false,
    connect_options: [timeout: 500],
    receive_timeout: 1_000
  ],
  notion_req_options: [
    plug: {Req.Test, Redactly.Integrations.Notion},
    retry: false,
    connect_options: [timeout: 500],
    receive_timeout: 1_000
  ],
  openai_req_options: [
    plug: {Req.Test, Redactly.Integrations.OpenAI},
    retry: false,
    connect_options: [timeout: 500],
    receive_timeout: 1_000
  ],
  fileutils_req_options: [
    plug: {Req.Test, Redactly.Integrations.FileUtils},
    retry: false,
    connect_options: [timeout: 500],
    receive_timeout: 1_000
  ]
