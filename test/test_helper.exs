ExUnit.start()
Application.put_env(:req, :finch, Redactly.Finch)
Ecto.Adapters.SQL.Sandbox.mode(Redactly.Repo, :manual)
