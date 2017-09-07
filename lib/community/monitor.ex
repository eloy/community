defmodule Community.Monitor do
  use GenServer

  defmacro __using__(_opts) do
    quote do
      @behaviour Community.Driver
      def start_link(opt \\ []) do
        Community.start_link(__MODULE__, opt)
      end
    end
  end


  def start_link(server_name, driver, opts) do
    GenServer.start_link(__MODULE__, {driver, opts}, name: server_name)
  end

  def init({driver, opts}) do
    #:net_kernel.monitor_nodes true
    ping_all()
    # join_group(@group)

    services = %{}
    refs = %{}
    conf = %{driver: driver, opts: opts}
    {:ok, {services, refs, conf}}
  end

  def handle_call({:monitor, service_id, service_pid, data, monitor_pid,}, _from, {services, refs, conf}) do
    {services, refs, conf} = monitor_service(service_id, service_pid, {services, refs, conf})
    {ref, {services, refs, conf}} = add_subscriptor(service_id, data, monitor_pid, {services, refs, conf})
    {:reply, {:ok, ref}, {services, refs, conf}}
  end


  def handle_call({:demonitor, service_id, ref}, _from, {services, refs, conf}) do
    Process.demonitor(ref)
    {{:subscriptor, service_id, subscriptor}, refs} = Map.pop refs, ref
    {_data, services} = pop_subscriptor(service_id, subscriptor, services)
    {:reply, :ok, {services, refs, conf}}
  end


  defp add_subscriptor(service_id, data, monitor_pid, {services, refs, conf}) do
    {process, ref, subscriptors} = Map.fetch! services, service_id
    subscriptors = Map.put(subscriptors, monitor_pid, data)
    services = Map.put services, service_id, {process, ref, subscriptors}
    {ref, refs} = monitor_subscriptor(service_id, monitor_pid, refs)
    {ref, {services, refs, conf}}
  end

  defp pop_subscriptor(service_id, subscriptor, services) do
    {process, ref, subscriptors} = Map.fetch! services, service_id
    {data, subscriptors} = Map.pop(subscriptors, subscriptor)
    services = Map.put services, service_id, {process, ref, subscriptors}
    {data, services}
  end

  defp monitor_service(service_id, process, {services, refs, conf}) do
    case Map.fetch services, service_id do
      {:ok, {process, ref, subscriptors}} -> {services, refs, conf}
      :error ->
        ref = Process.monitor process
        refs = Map.put refs, ref, {:service, service_id}
        services = Map.put services, service_id, {process, ref, %{}}
        {services, refs, conf}
    end
  end

  def monitor_subscriptor(service_id, subscriptor, refs) do
    ref = Process.monitor subscriptor
    refs = Map.put refs, ref, {:subscriptor, service_id, subscriptor}
    {ref, refs}
  end

  def replace_service(service_id, process, {services, refs, conf}) do
    ref = Process.monitor process
    refs = Map.put refs, ref, {:service, service_id}
    {_process, _ref, subscriptors} = Map.fetch! services, service_id
    services = Map.put services, service_id, {process, ref, subscriptors}
    {services, refs, conf}
  end

  defp ping_all do
    nodes = Community.Nodes.list
    Enum.each nodes, fn(node) ->
      Node.ping node
    end
  end

  defp join_group(group) do
    :pg2.create group
    :pg2.join group, self()
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    state = handle_down_event(ref, state)
    {:noreply, state}
  end

  defp handle_down_event(ref, {services, refs, conf}) do
    {data, refs} = Map.pop refs, ref
    case data do
      {:service, service_id} -> service_down(service_id, {services, refs, conf})
      {:subscriptor, service_id, subscriptor} -> subscriptor_down(service_id, subscriptor, {services, refs, conf})
    end
  end

  # Notifications
  #----------------------------------------------------------------------

  defp service_down(service_id, {services, refs, conf}) do
    {process, ref, subscriptors} = Map.fetch! services, service_id
    Enum.map subscriptors, fn({subscriptor, data}) ->
      send subscriptor, {:community_service_down, service_id, data}
    end
    conf.driver.handle_community({:community_service_down, service_id}, conf.opts)
    eval_restart_service(service_id, {services, refs, conf})
  end

  defp subscriptor_down(service_id, subscriptor, {services, refs, conf}) do
    {process, _ref, _subscriptors} = Map.fetch! services, service_id
    {data, services} = pop_subscriptor(service_id, subscriptor, services)
    send process, {:community_subscriptor_down, service_id, data}

    conf.driver.handle_community({:community_subscriptor_down, service_id, data}, conf.opts)

    {services, refs, conf}
  end

  def service_replaced(service_id, new_process, {services, _refs, _conf}) do
    {_process, _ref, subscriptors} = Map.fetch! services, service_id
    Enum.map subscriptors, fn({subscriptor, data}) ->
      send subscriptor, {:community_service_replaced, service_id, new_process}
    end
    :ok
  end

  # Service restart
  #----------------------------------------------------------------------


  def handle_info({:restart_service, service_id}, state)do
    state = eval_restart_service(service_id, state)
    {:noreply, state}
  end

  def eval_restart_service(service_id, {_services, _refs, conf} = state) do
    case conf.driver.start_service(service_id, conf.opts) do
      {:ok, pid} ->
        state = replace_service(service_id, pid, state)
        :ok = service_replaced(service_id, pid, state)
        state
      :retry ->
        Process.send_after self(), {:restart_service, service_id}, 5000
        state
      {:retry, timeout} ->
        Process.send_after self(), {:restart_service, service_id}, timeout
        state
      _ -> state
    end
  end
end
