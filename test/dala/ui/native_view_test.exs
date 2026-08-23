defmodule Dala.Ui.NativeViewTest do
  use ExUnit.Case, async: false

  alias Dala.Ui.NativeView

  defmodule Counter do
    use Dala.Ui.NativeView

    def mount(props, socket) do
      {:ok, Dala.Socket.assign(socket, :count, props[:count] || 0)}
    end

    # NativeView components return their PROP MAP (merged into the node's
    # props alongside :module/:id/:component_handle) — not a node map.
    def render(assigns) do
      %{text: "count: #{assigns.count}"}
    end

    def handle_event("inc", _payload, socket),
      do: {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}

    def handle_info({:add, n}, socket),
      do: {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + n)}
  end

  setup do
    NativeView.init_module_name_cache()
    start_supervised!(Dala.Ui.NativeView.Registry)
    :ok
  end

  defp text_node(text), do: %{type: :text, props: %{text: text}, children: []}

  defp start_counter(id) do
    node = %{type: :native_view, props: %{module: Counter, id: id}, children: []}
    {expanded, active} = NativeView.expand(node, self(), :no_render)
    pid = Dala.Ui.NativeView.Registry.lookup(self(), id, Counter) |> elem(1)
    {expanded, active, pid}
  end

  describe "expand/3" do
    test "passes a plain tree through untouched" do
      tree = %{type: :column, props: %{}, children: [text_node("hi")]}
      {expanded, active} = NativeView.expand(tree, self(), :no_render)

      assert expanded == tree
      assert MapSet.size(active) == 0
    end

    test "accepts a list of root nodes (what render/1 returns)" do
      trees = [text_node("a"), text_node("b")]
      {expanded, active} = NativeView.expand(trees, self(), :no_render)

      assert expanded == trees
      assert MapSet.size(active) == 0
    end

    test "expands a native_view node into serialisable form" do
      node = %{
        type: :native_view,
        props: %{module: Counter, id: :counter1, count: 5},
        children: []
      }

      {expanded, active} = NativeView.expand(node, self(), :no_render)

      assert expanded.props.module == "Dala_Ui_NativeViewTest_Counter"
      assert expanded.props.id == "counter1"
      # :no_render platform yields handle 0 — no NIF round-trip in tests
      assert expanded.props.component_handle == 0
      assert expanded.children == []

      assert MapSet.equal?(active, MapSet.new([{:counter1, Counter}]))
    end

    test "renders the component's own assigns" do
      node = %{type: :native_view, props: %{module: Counter, id: :c}, children: []}
      {expanded, _} = NativeView.expand(node, self(), :no_render)

      assert expanded.props.text == "count: 0"
    end

    test "reuses the component process across renders and pushes new props" do
      node = %{type: :native_view, props: %{module: Counter, id: :same}, children: []}

      {first, _} = NativeView.expand(node, self(), :no_render)

      {second, active} =
        NativeView.expand(
          %{node | props: %{module: Counter, id: :same, count: 9}},
          self(),
          :no_render
        )

      assert first.props.component_handle == second.props.component_handle
      assert second.props.text == "count: 9"
      assert MapSet.equal?(active, MapSet.new([{:same, Counter}]))
    end

    test "walks children recursively around native views" do
      tree = %{
        type: :column,
        props: %{},
        children: [
          text_node("before"),
          %{type: :native_view, props: %{module: Counter, id: :nested}, children: []},
          text_node("after")
        ]
      }

      {expanded, active} = NativeView.expand(tree, self(), :no_render)

      assert hd(expanded.children).props.text == "before"
      assert List.last(expanded.children).props.text == "after"
      nested = Enum.at(expanded.children, 1)
      assert nested.props.component_handle == 0
      assert MapSet.to_list(active) == [{:nested, Counter}]
    end

    test "raises when module or id are missing/not atoms" do
      assert_raise ArgumentError, ~r/requires :module and :id as atoms/, fn ->
        NativeView.expand(
          %{type: :native_view, props: %{id: :x}, children: []},
          self(),
          :no_render
        )
      end

      assert_raise ArgumentError, ~r/requires :module and :id as atoms/, fn ->
        NativeView.expand(
          %{type: :native_view, props: %{module: Counter}, children: []},
          self(),
          :no_render
        )
      end
    end
  end

  describe "plugin component expansion" do
    defmodule ChartPlugin do
      use Dala.Plugin

      import Dala.Plugin

      description("test chart")

      component "test_chart" do
        prop("series", :map)
        capability(:gestures)
      end
    end

    setup do
      start_supervised!(Dala.Plugin.Registry)
      Dala.Plugin.Registry.register(ChartPlugin)
      :ok
    end

    test "plugin-registered component types expand like native views" do
      node = %{type: "test_chart", props: %{id: :chart1, series: []}, children: []}
      {expanded, active} = NativeView.expand(node, self(), :no_render)

      assert expanded.props.id == "chart1"
      assert expanded.props.module == "test_chart"
      assert expanded.props.component_handle == 0
      assert MapSet.to_list(active) == [{:chart1, {:plugin_component, "test_chart"}}]
    end

    test "plugin components require an :id prop" do
      assert_raise ArgumentError, ~r/requires :id prop/, fn ->
        NativeView.expand(
          %{type: "test_chart", props: %{}, children: []},
          self(),
          :no_render
        )
      end
    end
  end

  describe "registry lifecycle" do
    test "duplicate ids on the same screen raise" do
      start_counter(:dup)

      # A different pid under the same {screen, id, module} key must raise.
      assert_raise ArgumentError, ~r/duplicate id :dup/, fn ->
        Dala.Ui.NativeView.Registry.register(self(), :dup, Counter, self())
      end
    end

    test "re-registering the same pid is a no-op" do
      {_expanded, _active, pid} = start_counter(:re_reg)

      assert :ok = Dala.Ui.NativeView.Registry.register(self(), :re_reg, Counter, pid)
      assert {:ok, ^pid} = Dala.Ui.NativeView.Registry.lookup(self(), :re_reg, Counter)
    end

    test "deregister removes the entries" do
      start_counter(:gone)

      :ok = Dala.Ui.NativeView.Registry.deregister(self(), :gone, Counter)
      assert {:error, :not_found} = Dala.Ui.NativeView.Registry.lookup(self(), :gone, Counter)
    end

    test "reconcile stops components that left the tree and keeps active ones" do
      {_e1, _a1, kept_pid} = start_counter(:kept)
      {_e2, _a2, reaped_pid} = start_counter(:reaped)

      # Only :kept is present in this render's active set. Monitor before
      # reconciling — the shutdown exit lands quickly.
      reap_ref = Process.monitor(reaped_pid)
      active_keys = MapSet.new([{:kept, Counter}])

      :ok = Dala.Ui.NativeView.Registry.reconcile(self(), active_keys)

      assert Process.alive?(kept_pid)
      {:ok, still_there} = Dala.Ui.NativeView.Registry.lookup(self(), :kept, Counter)
      assert still_there == kept_pid

      assert_receive {:DOWN, ^reap_ref, :process, _, :shutdown}, 1000
      assert {:error, :not_found} = Dala.Ui.NativeView.Registry.lookup(self(), :reaped, Counter)
    end

    test "graceful component stop deregisters itself" do
      {_expanded, _active, pid} = start_counter(:terminating)

      # GenServer.stop runs terminate/2, which deregisters from the registry.
      ref = Process.monitor(pid)
      :ok = GenServer.stop(pid, :normal)
      assert_receive {:DOWN, ^ref, :process, _, _}, 1000

      assert {:error, :not_found} =
               Dala.Ui.NativeView.Registry.lookup(self(), :terminating, Counter)
    end
  end

  describe "component events and messages" do
    test "dispatch/3 runs handle_event and notifies the screen" do
      {_expanded, _active, pid} = start_counter(:events)

      :ok = NativeView.Server.dispatch(pid, "inc", %{})

      assert_receive {:component_changed, :events, Counter}, 1000
      wait_until(fn -> NativeView.Server.render_props(pid) == %{text: "count: 1"} end)
    end

    test "handle_info messages are forwarded to the component" do
      {_expanded, _active, pid} = start_counter(:info_fwd)

      send(pid, {:add, 5})
      wait_until(fn -> NativeView.Server.render_props(pid) == %{text: "count: 5"} end)
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
end
