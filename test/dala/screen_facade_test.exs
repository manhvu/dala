defmodule Dala.ScreenFacadeTest do
  @moduledoc "Exercises the Dala.Screen facade delegates against a live screen process."

  use ExUnit.Case, async: false

  defmodule DemoScreen do
    use Dala.Screen

    def mount(_params, _session, socket) do
      {:ok, Dala.Socket.assign(socket, :loaded, true)}
    end

    def render(_socket), do: %{type: :column, props: %{}, children: []}

    def handle_event("ping", _params, socket) do
      {:noreply, Dala.Socket.assign(socket, :pinged, true)}
    end

    def handle_info(_, socket), do: {:noreply, socket}
  end

  setup do
    start_supervised!(Dala.Screen.Manager)
    {:ok, pid} = Dala.Screen.start_link(DemoScreen, %{})
    %{pid: pid}
  end

  test "start_link/3 mounts the screen", %{pid: pid} do
    assert Dala.Screen.get_current_module(pid) == DemoScreen
    assert Dala.Screen.get_socket(pid).assigns.loaded == true
  end

  test "dispatch/3 delivers events", %{pid: pid} do
    :ok = Dala.Screen.dispatch(pid, "ping", %{})

    eventually(fn -> Dala.Screen.get_socket(pid).assigns[:pinged] == true end)
    assert Dala.Screen.get_socket(pid).assigns.pinged == true
  end

  test "nav history is empty for a freshly mounted root screen", %{pid: pid} do
    assert [] = Dala.Screen.get_nav_history(pid)
  end

  test "list/1 tracks registered screens", %{pid: pid} do
    eventually(fn ->
      Enum.any?(Dala.Screen.list(), fn s -> s.pid == pid and s.module == DemoScreen end)
    end)

    entry = Enum.find(Dala.Screen.list(), fn s -> s.module == DemoScreen end)
    assert %{id: _, name: _, pid: ^pid, module: DemoScreen} = entry
  end

  defp eventually(fun, tries \\ 50)

  defp eventually(_fun, 0), do: flunk("condition never became true")

  defp eventually(fun, tries) do
    unless fun.() do
      Process.sleep(10)
      eventually(fun, tries - 1)
    end
  end
end
