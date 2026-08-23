defmodule Dala.Event.EventTest do
  use ExUnit.Case, async: true

  alias Dala.Event.{Address, Event, Target, Trace}

  @scope %{screen_pid: nil, component_chain: []}

  defp addr(overrides \\ []) do
    Address.new(Keyword.merge([screen: MyScreen, widget: :button, id: :save], overrides))
  end

  # ── dispatch/4 ──────────────────────────────────────────────────────────────

  test "dispatch/4 delivers the canonical envelope" do
    address = addr()

    :ok = Event.dispatch(self(), address, :tap, %{x: 1})

    assert_received {:dala_event, ^address, :tap, %{x: 1}}
  end

  test "dispatch/4 broadcasts to trace subscribers" do
    Trace.start()
    Trace.subscribe()
    on_exit(&Trace.unsubscribe/0)

    address = addr()
    :ok = Event.dispatch(self(), address, :tap, nil)

    assert_received {:dala_trace, ^address, :tap, nil}
    assert_received {:dala_event, ^address, :tap, nil}
  end

  # ── emit/5 ──────────────────────────────────────────────────────────────────

  test "emit/5 delivers to a direct pid target" do
    :ok = Event.emit(addr(), :change, "v", self(), %{@scope | screen_pid: self()})

    assert_received {:dala_event, %Address{id: :save}, :change, "v"}
  end

  test "emit/5 resolves :screen through the render scope" do
    :ok = Event.emit(addr(), :tap, nil, :screen, %{@scope | screen_pid: self()})

    assert_received {:dala_event, %Address{}, :tap, nil}
  end

  test "emit/5 resolves :parent from the component chain" do
    me = self()

    parent =
      spawn_link(fn ->
        receive do
          msg -> send(me, {:relayed, msg})
        end
      end)

    scope = %{@scope | screen_pid: me, component_chain: [{:form, parent}]}

    :ok = Event.emit(addr(), :submit, nil, :parent, scope)

    assert_receive({:relayed, {:dala_event, %Address{}, :submit, nil}})
  end

  test "emit/5 resolves {:component, id} from the chain" do
    me = self()

    comp =
      spawn_link(fn ->
        receive do
          msg -> send(me, {:comp_got, msg})
        end
      end)

    scope = %{@scope | screen_pid: me, component_chain: [{:chart, comp}]}

    :ok = Event.emit(addr(), :refresh, nil, {:component, :chart}, scope)

    assert_receive({:comp_got, {:dala_event, %Address{}, :refresh, nil}})
  end

  test "emit/5 drops events for unresolvable targets without raising" do
    dead = spawn(fn -> :ok end)
    wait_until_dead(dead)

    scope = %{@scope | screen_pid: self(), component_chain: []}

    assert :ok == Event.emit(addr(), :tap, nil, dead, scope)
    assert :ok == Event.emit(addr(), :tap, nil, :never_registered_anywhere, scope)
    assert :ok == Event.emit(addr(), :tap, nil, {:component, :missing}, scope)
    assert :ok == Event.emit(addr(), :tap, nil, 1234, scope)

    refute_received({:dala_event, _, _, _})
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  test "is_event?/1 recognises only canonical envelopes" do
    envelope = {:dala_event, addr(), :tap, nil}

    assert Event.is_event?(envelope)
    refute Event.is_event?({:tap, :something})
    refute Event.is_event?({:dala_event, %{}, :tap, nil})
    refute Event.is_event?(:nope)
  end

  test "match_address?/2 requires every filter to match" do
    address = addr(widget: :button, id: :save, instance: 3)

    assert Event.match_address?(address, widget: :button)
    assert Event.match_address?(address, widget: :button, id: :save)
    assert Event.match_address?(address, instance: 3)
    refute Event.match_address?(address, widget: :text_field)
    refute Event.match_address?(address, widget: :button, id: :cancel)
  end

  test "send_test/7 synthesises a full delivery with defaults and overrides" do
    :ok = Event.send_test(self(), MyScreen, :list, :row, :select, %{index: 2})

    assert_received {:dala_event,
                     %Address{screen: MyScreen, widget: :list, id: :row, component_path: []},
                     :select, %{index: 2}}

    :ok =
      Event.send_test(self(), MyScreen, :button, :save, :long_press, nil,
        component_path: [:form],
        instance: 7
      )

    assert_received {:dala_event, %Address{component_path: [:form], instance: 7}, :long_press,
                     nil}
  end

  test "Target.classify/1 separates in-tree from external targets" do
    assert Target.classify(:parent) == :in_tree
    assert Target.classify(:screen) == :in_tree
    assert Target.classify({:component, :x}) == :in_tree
    assert Target.classify(self()) == :external
    assert Target.classify(:some_name) == :external
  end

  # ── Dala.Event facade ───────────────────────────────────────────────────────

  test "Dala.Event re-exports the unified API" do
    address = addr()

    assert :ok == Dala.Event.dispatch(self(), address, :tap, nil)
    assert_received {:dala_event, ^address, :tap, nil}

    assert :ok == Dala.Event.emit(address, :change, "v", self(), %{@scope | screen_pid: self()})
    assert_received {:dala_event, %Address{id: :save}, :change, "v"}

    assert Dala.Event.is_event?({:dala_event, address, :tap, nil})
    assert Dala.Event.match_address?(address, id: :save)
    assert :ok == Dala.Event.send_test(self(), MyScreen, :button, :x, :tap)

    assert_received {:dala_event, %Address{id: :x}, :tap, nil}
  end

  defp wait_until_dead(pid, attempts \\ 50)

  defp wait_until_dead(_pid, 0), do: flunk("process never died")

  defp wait_until_dead(pid, attempts) do
    if Process.alive?(pid) do
      Process.sleep(10)
      wait_until_dead(pid, attempts - 1)
    end
  end
end
