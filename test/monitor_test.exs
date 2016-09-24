defmodule MonitorTest do
  use ExUnit.Case
  doctest Community


  defmodule TestMonitor do
    use Community.Monitor, otp_app: :community
    def nodes_list do
      []
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

    def start_link(service_pid) do
      GenServer.start_link(__MODULE__, service_pid)
    end

    def init(service_pid) do
      TestMonitor.monitor :test_service, service_pid, {:foo}
      {:ok, {service_pid}}
    end
  end

  describe "monotoring servives" do
    test "monitor services" do
      {:ok, pid} = TestMonitor.start_link
      {:ok, service} = TestService.start_link
      service_name = :test_service
      data = {:foo, :bar}
      TestMonitor.monitor service_name, service, data
      GenServer.stop service
      assert_receive {:community_service_down, service_name, data}
    end

    test "monitor nodes" do
      {:ok, pid} = TestMonitor.start_link
      {:ok, subscriptor} = TestSubscriptor.start_link(self())
      GenServer.stop subscriptor
      assert_receive {:community_subscriptor_down, :test_service, {:foo}}
    end
  end

end
