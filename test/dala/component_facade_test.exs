defmodule Dala.ComponentFacadeTest do
  @moduledoc """
  Exercises the `Dala.Component` / `Dala.ComponentRegistry` / `Dala.ComponentServer`
  facade modules against their NativeView implementations.
  """

  use ExUnit.Case, async: false

  alias Dala.Component
  alias Dala.ComponentRegistry
  alias Dala.ComponentServer

  defmodule Counter do
    use Dala.Ui.NativeView

    def mount(props, socket) do
      {:ok, Dala.Socket.assign(socket, :count, props[:count] || 0)}
    end

    def render(assigns), do: %{text: "count: #{assigns.count}"}

    def handle_event("inc", _payload, socket),
      do: {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end

  setup do
    Dala.Ui.NativeView.init_module_name_cache()
    # The facade defdelegate has no child_spec — start the implementation
    start_supervised!(Dala.Ui.NativeView.Registry)
    :ok
  end

  defp counter_node(id),
    do: %{type: :native_view, props: %{module: Counter, id: id}, children: []}

  test "Dala.Component.expand/3 delegates to NativeView" do
    {expanded, active} = Component.expand(counter_node(:via_facade), self(), :no_render)

    assert expanded.props.component_handle == 0
    assert expanded.props.text == "count: 0"
    assert MapSet.to_list(active) == [{:via_facade, Counter}]
  end

  test "ComponentRegistry register/lookup/deregister round trip" do
    screen = self()

    component_pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    :ok = ComponentRegistry.register(screen, :row1, Counter, component_pid)
    assert {:ok, ^component_pid} = ComponentRegistry.lookup(screen, :row1, Counter)

    :ok = ComponentRegistry.deregister(screen, :row1, Counter)
    assert {:error, :not_found} = ComponentRegistry.lookup(screen, :row1, Counter)

    send(component_pid, :stop)
  end

  test "ComponentRegistry.lookup/3 misses for unknown ids" do
    assert {:error, :not_found} = ComponentRegistry.lookup(self(), :nope, Counter)
  end

  test "ComponentRegistry.reconcile/2 reaps components absent from the active set" do
    screen = self()

    kept =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    reaped =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    reap_ref = Process.monitor(reaped)

    :ok = ComponentRegistry.register(screen, :kept, Counter, kept)
    :ok = ComponentRegistry.register(screen, :reaped, Counter, reaped)

    :ok = ComponentRegistry.reconcile(screen, MapSet.new([{:kept, Counter}]))

    assert_receive {:DOWN, ^reap_ref, :process, _, _}, 1000
    assert {:error, :not_found} = ComponentRegistry.lookup(screen, :reaped, Counter)
    assert {:ok, ^kept} = ComponentRegistry.lookup(screen, :kept, Counter)

    send(kept, :stop)
  end

  test "ComponentServer start/render_props/get_handle/update/dispatch lifecycle" do
    {:ok, pid} =
      ComponentServer.start(
        module: Counter,
        id: :server_facade,
        screen_pid: self(),
        props: %{count: 7},
        platform: :no_render
      )

    wait_until(fn -> ComponentServer.render_props(pid) == %{text: "count: 7"} end)

    assert ComponentServer.get_handle(pid) == 0

    :ok = ComponentServer.update(pid, %{count: 8})
    wait_until(fn -> ComponentServer.render_props(pid) == %{text: "count: 8"} end)

    :ok = ComponentServer.dispatch(pid, "inc", %{})
    wait_until(fn -> ComponentServer.render_props(pid) == %{text: "count: 9"} end)

    GenServer.stop(pid, :normal)
  end

  defp wait_until(fun, tries \\ 50)

  defp wait_until(fun, 0), do: fun.()

  defp wait_until(fun, tries) do
    try do
      fun.()
    rescue
      _ ->
        Process.sleep(10)
        wait_until(fun, tries - 1)
    end
  end
end
