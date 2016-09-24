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

      def monitor(service_name,  process, data, monitor_pid \\ self()) do
        GenServer.call @server_name, {:monitor, service_name, process, data, monitor_pid}
      end

      def init(opt) do
        #:net_kernel.monitor_nodes true
        ping_all()
        # join_group(@group)

        services = %{}
        refs = %{}
        {:ok, {services, refs}}
      end

      def handle_call({:monitor, service_name, process, data, monitor_pid,}, _from, {services, refs}) do
        refs = monitor_service(service_name, process, refs)
        refs = monitor_subscriptor(service_name, process, monitor_pid, refs)
        services = add_subscriptor(service_name, process, data, monitor_pid, services)

        {:reply, :ok, {services, refs}}
      end

      defp add_subscriptor(service_name, process, data, monitor_pid, services) do
        service = Map.get services, service_name, %{}
        subscriptors = Map.get(service, process, %{}) |> Map.put(monitor_pid, data)
        service = Map.put service, process, subscriptors
        Map.put services, service_name, service
      end

      defp pop_subscriptor(service_name, process, subscriptor, services) do
        service = Map.fetch! services, service_name
        subscriptors = Map.fetch! service, process

        {data, subscriptors} = Map.pop subscriptors, subscriptor
        service = Map.put service, process, subscriptors
        services = Map.put services, service_name, service
        {data, services}
      end


      def monitor_service(service_name, process, refs) do
        case Map.fetch refs, process do
          {:ok, ref} -> refs
          :error ->
            ref = Process.monitor process
            Map.put refs, ref, {:service, service_name, process}
        end
      end

      def monitor_subscriptor(service_name, process, subscriptor, refs) do
        ref = Process.monitor subscriptor
        Map.put refs, ref, {:subscriptor, service_name, process, subscriptor}
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
          {:ok, {:service, service_name, process}} -> service_down(service_name, process, {services, refs})
          {:ok, {:subscriptor, service_name, process, subscriptor}} -> subscriptor_down(service_name, process, subscriptor, {services, refs})
          :error -> {services, refs}
        end
      end


      defp service_down(service_name, process, {services, refs}) do
        service = Map.fetch! services, service_name
        subscriptors = Map.fetch! service, process
        Enum.map subscriptors, fn({subscriptor, data}) ->
          send subscriptor, {:community_service_down, service_name, data}
        end

        {services, refs}
      end

      defp subscriptor_down(service_name, process, subscriptor, {services, refs}) do
        {data, services} = pop_subscriptor(service_name, process, subscriptor, services)
        send process, {:community_subscriptor_down, service_name, data}
        {services, refs}
      end
    end
  end

end
