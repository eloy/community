defmodule Community.Nodes do
  use GenServer

  @server_name :community_nodes_server

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: @server_name)
  end

  def list do
    GenServer.call @server_name, :list
  end

  def init() do
    nodes = Application.get_env(:community, :nodes) || []
    {:ok, nodes}
  end

  def handle_call(:list, _from, nodes) do
    {:reply, nodes, nodes}
  end
end
