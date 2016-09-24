defmodule Community.Monitor do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour :gen_server

      @otp_app Keyword.fetch!(opts, :otp_app)
      @server_name __MODULE__

      def start_link() do
        IO.puts "start_link server: #{@server_name}"
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
        refs = monitor_service(service_id, process, refs)
        refs = monitor_subscriptor(service_id, process, monitor_pid, refs)
        services = add_subscriptor(service_id, process, data, monitor_pid, services)

        {:reply, :ok, {services, refs}}
      end

      defp add_subscriptor(service_id, process, data, monitor_pid, services) do
        service = Map.get services, service_id, %{}
        subscriptors = Map.get(service, process, %{}) |> Map.put(monitor_pid, data)
        service = Map.put service, process, subscriptors
        Map.put services, service_id, service
      end

      defp pop_subscriptor(service_id, process, subscriptor, services) do
        service = Map.fetch! services, service_id
        subscriptors = Map.fetch! service, process

        {data, subscriptors} = Map.pop subscriptors, subscriptor
        service = Map.put service, process, subscriptors
        services = Map.put services, service_id, service
        {data, services}
      end


      defp monitor_service(service_id, process, refs) do
        case Map.fetch refs, process do
          {:ok, ref} -> refs
          :error ->
            ref = Process.monitor process
            Map.put refs, ref, {:service, service_id, process}
        end
      end


      def monitor_subscriptor(service_id, process, subscriptor, refs) do
        ref = Process.monitor subscriptor
        Map.put refs, ref, {:subscriptor, service_id, process, subscriptor}
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

        case Map.fetch refs, ref do
          {:ok, {:service, service_id, process}} -> service_down(service_id, process, {services, refs})
          {:ok, {:subscriptor, service_id, process, subscriptor}} -> subscriptor_down(service_id, process, subscriptor, {services, refs})
          :error -> {services, refs}
        end
      end


      defp service_down(service_id, process, {services, refs}) do
        service = Map.fetch! services, service_id
        subscriptors = Map.fetch! service, process
        Enum.map subscriptors, fn({subscriptor, data}) ->
          send subscriptor, {:community_service_down, service_id, data}
        end

        handle_community({:community_service_down, service_id})
        eval_restart_service(service_id)
        {services, refs}
      end

      defp subscriptor_down(service_id, process, subscriptor, {services, refs}) do
        {data, services} = pop_subscriptor(service_id, process, subscriptor, services)
        send process, {:community_subscriptor_down, service_id, data}
        handle_community({:community_subscriptor_down, service_id, data})
        {services, refs}
      end

      # Service restart
      #----------------------------------------------------------------------


      def handle_info({:restart_service, service_id}, {service, refs})do
        eval_restart_service(service_id)
        {:noreply, {service, refs}}
      end

      def eval_restart_service(service_id) do
        case start_service(service_id) do
          {:ok, new_pid} -> :ok
          :retry -> Process.send_after self(), {:restart_service, service_id}, 5000
          {:retry, timeout} -> Process.send_after self(), {:restart_service, service_id}, timeout
          _ -> :ok
        end
      end
    end
  end

end
