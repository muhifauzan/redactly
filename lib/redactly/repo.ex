defmodule Redactly.Repo do
  use Ecto.Repo,
    otp_app: :redactly,
    adapter: Ecto.Adapters.Postgres
end
