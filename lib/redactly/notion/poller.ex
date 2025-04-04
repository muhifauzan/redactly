defmodule Redactly.Notion.Poller do
  @moduledoc """
  Periodically polls the configured Notion database(s) for new tickets.
  """

  use GenServer

  alias Redactly.Notion

  @poll_interval_ms 15_000

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    Notion.poll_for_tickets()
    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end
end
