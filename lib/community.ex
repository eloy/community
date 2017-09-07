defmodule Community do
  use Supervisor

  @monitor_name :community_monitor_server

  def start_link(driver, opts) do
    Supervisor.start_link(__MODULE__, {driver, opts})
  end

  def init({driver, monitor_opts}) do
    children = [
      worker(Community.Nodes, []),
      worker(Community.Monitor, [@monitor_name, driver, monitor_opts]),
    ]
    opts = [strategy: :one_for_one, name: Community.Supervisor]

    # supervise/2 is imported from Supervisor.Spec
    supervise(children, opts)
  end

  def monitor(service_id,  process, data, monitor_pid \\ self()) do
    GenServer.call @monitor_name, {:monitor, service_id, process, data, monitor_pid}
  end


  def demonitor(service_id, ref) do
    GenServer.call @monitor_name, {:demonitor, service_id, ref}
  end

end
