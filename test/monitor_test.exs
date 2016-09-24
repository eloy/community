defmodule MonitorTest do
  use ExUnit.Case
  doctest Community


  defmodule TestMonitor do
    use Community.Monitor, otp_app: :community
    def nodes_list do
      []
    end

    def handle_community(msg) do
      :ok
    end

    def start_service(msg) do
      :ok
    end
  end

  defmodule TestService do
    use GenServer

    def start_link() do
      GenServer.start_link(__MODULE__, :ok)
    end

    def init(:ok) do
      {:ok, {}}
    end
  end

  defmodule TestSubscriptor do
    use GenServer

    def start_link(service_pid, service_id, data \\ {}) do
      GenServer.start_link(__MODULE__, {service_pid, service_id, data})
    end

    def init({service_pid, service_id, data}) do
      TestMonitor.monitor service_id, service_pid, data
      {:ok, {service_pid, service_id, data}}
    end
  end

  describe "monotoring servives" do
    test "monitor services" do
      {:ok, pid} = TestMonitor.start_link
      {:ok, service} = TestService.start_link
      service_id = {:test_service, 1}
      data = {:foo, :bar}
      TestMonitor.monitor service_id, service, data
      GenServer.stop service
      assert_receive {:community_service_down, service_id, data}
    end

    test "monitor nodes" do
      service_id = {:test_service, 1}
      data = {:foo, :bar}
      {:ok, pid} = TestMonitor.start_link
      {:ok, subscriptor} = TestSubscriptor.start_link(self(), service_id, data)
      GenServer.stop subscriptor
      assert_receive {:community_subscriptor_down, service_id, data}
    end
  end

end
