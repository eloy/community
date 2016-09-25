defmodule MonitorTest do
  use ExUnit.Case
  doctest Community


  defmodule TestMonitor do
    use Community.Monitor

    def handle_community(msg, pid) do
      send pid, {:handle_community, msg}
    end

    def start_service(service_id, pid) do
      send pid, {:start_service, service_id}
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
      Community.monitor service_id, service_pid, data
      {:ok, {service_pid, service_id, data}}
    end
  end

  describe "monitoring servives" do
    test "monitor services" do
      {:ok, _pid} = TestMonitor.start_link self()
      {:ok, service} = TestService.start_link
      service_id = {:test_service, 1}
      data = {:foo, :bar}
      Community.monitor service_id, service, data
      GenServer.stop service
      assert_receive {:community_service_down, ^service_id, ^data}
      assert_receive {:handle_community, {:community_service_down, ^service_id}}
      assert_receive {:start_service, ^service_id}
    end

    test "monitor nodes" do
      service_id = {:test_service, 1}
      data = {:foo, :bar}
      {:ok, _pid} = TestMonitor.start_link self()
      {:ok, subscriptor} = TestSubscriptor.start_link(self(), service_id, data)
      GenServer.stop subscriptor
      assert_receive {:community_subscriptor_down, ^service_id, ^data}
      assert_receive {:handle_community, {:community_subscriptor_down, ^service_id, ^data}}
    end
  end

end
