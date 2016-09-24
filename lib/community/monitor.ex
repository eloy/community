defmodule Community.Monitor do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour :gen_server

      @otp_app Keyword.fetch!(opts, :otp_app)
      @server_name __MODULE__

      def start_link() do
        GenServer.start_link(__MODULE__, :opt, name: @server_name)
      end

      def monitor(service_id,  process, data, monitor_pid \\ self()) do
        GenServer.call @server_name, {:monitor, service_id, process, data, monitor_pid}
      end

      def init(opt) do
        #:net_kernel.monitor_nodes true
        ping_all()
        # join_group(@group)

        services = %{}
        refs = %{}
        {:ok, {services, refs}}
      end

      # def handle_community(message)
      # def start_service(service_id)

      def handle_call({:monitor, service_id, process, data, monitor_pid,}, _from, {services, refs}) do
        {services, refs} = monitor_service(service_id, process, {services, refs})
        {services, refs} = add_subscriptor(service_id, data, monitor_pid, {services, refs})
        {:reply, :ok, {services, refs}}
      end

      defp add_subscriptor(service_id, data, monitor_pid, {services, refs}) do
        {process, ref, subscriptors} = Map.fetch! services, service_id
        subscriptors = Map.put(subscriptors, monitor_pid, data)
        services = Map.put services, service_id, {process, ref, subscriptors}
        refs = monitor_subscriptor(service_id, monitor_pid, refs)
        {services, refs}
      end

      defp pop_subscriptor(service_id, subscriptor, services) do
        {process, ref, subscriptors} = Map.fetch! services, service_id
        {data, subscriptors} = Map.pop(subscriptors, subscriptor)
        services = Map.put services, service_id, {process, ref, subscriptors}
        {data, services}
      end

      defp monitor_service(service_id, process, {services,refs}) do
        case Map.fetch services, service_id do
          {:ok, {process, ref, subscriptors}} -> {services, refs}
          :error ->
            ref = Process.monitor process
            refs = Map.put refs, ref, {:service, service_id}
            services = Map.put services, service_id, {process, ref, %{}}
            {services, refs}
        end
      end

      def monitor_subscriptor(service_id, subscriptor, refs) do
        ref = Process.monitor subscriptor
        Map.put refs, ref, {:subscriptor, service_id, subscriptor}
      end

      def replace_service(service_id, process, {services, refs}) do
        ref = Process.monitor process
        refs = Map.put refs, ref, {:service, service_id}
        {_process, _ref, subscriptors} = Map.fetch! services, service_id
        services = Map.put services, service_id, {process, ref, subscriptors}
        {services, refs}
      end

      defp ping_all do
        Enum.each nodes_list, fn(node) ->
          Node.ping node
        end
      end

      defp join_group(group) do
        :pg2.create group
        :pg2.join group, self()
      end

      def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
        state = handle_down(ref, state)
        {:noreply, state}
      end

      defp handle_down(ref, {services, refs}) do
        {data, refs} = Map.pop refs, ref
        case data do
          {:service, service_id} -> service_down(service_id, {services, refs})
          {:subscriptor, service_id, subscriptor} -> subscriptor_down(service_id, subscriptor, {services, refs})
        end
      end

      # Notifications
      #----------------------------------------------------------------------

      defp service_down(service_id, {services, refs}) do
        {process, ref, subscriptors} = Map.fetch! services, service_id
        Enum.map subscriptors, fn({subscriptor, data}) ->
          send subscriptor, {:community_service_down, service_id, data}
        end

        handle_community({:community_service_down, service_id})
        eval_restart_service(service_id, {services, refs})
      end

      defp subscriptor_down(service_id, subscriptor, {services, refs}) do
        {process, _ref, _subscriptors} = Map.fetch! services, service_id
        {data, services} = pop_subscriptor(service_id, subscriptor, services)
        send process, {:community_subscriptor_down, service_id, data}
        handle_community({:community_subscriptor_down, service_id, data})
        {services, refs}
      end

      def service_replaced(service_id, new_process, {services, _refs}) do
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

      def eval_restart_service(service_id, state) do
        case start_service(service_id) do
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
  end

end
