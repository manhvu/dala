defmodule Dala.Platform.PubSubTest do
  use ExUnit.Case, async: true

  alias Dala.Platform.PubSub

  defp unique_name do
    :"dala_pubsub_test_#{System.unique_integer([:positive])}"
  end

  defp start_pubsub do
    name = unique_name()
    {:ok, pid} = PubSub.start_link(name: name)
    on_exit(fn -> Process.exit(pid, :kill) end)
    name
  end

  defp start_subscriber(pubsub, topic, parent) do
    spawn_link(fn ->
      :ok = PubSub.subscribe(pubsub, topic)
      send(parent, :ready)
      relay_loop(parent)
    end)
  end

  defp relay_loop(parent) do
    receive do
      :stop ->
        :ok

      msg ->
        send(parent, {:relay, msg})
        relay_loop(parent)
    end
  end

  test "start_link/1 requires a :name option" do
    assert_raise(KeyError, fn -> PubSub.start_link([]) end)
  end

  test "child_spec/1 uses the pubsub name as id" do
    name = unique_name()

    assert %{id: ^name, start: {PubSub, :start_link, [[name: ^name]]}, type: :supervisor} =
             PubSub.child_spec(name: name)
  end

  test "broadcast/3 delivers to every subscriber of the topic" do
    pubsub = start_pubsub()
    me = self()

    worker = start_subscriber(pubsub, "user:1", me)
    assert_receive(:ready)

    :ok = PubSub.subscribe(pubsub, "user:1")
    :ok = PubSub.broadcast(pubsub, "user:1", {:update, %{id: 1}})

    assert_receive({:update, %{id: 1}})
    assert_receive({:relay, {:update, %{id: 1}}})

    send(worker, :stop)
  end

  test "broadcast/3 only reaches the given topic" do
    pubsub = start_pubsub()

    :ok = PubSub.subscribe(pubsub, "a")
    :ok = PubSub.broadcast(pubsub, "b", :wrong_topic)

    refute_receive(:wrong_topic)

    :ok = PubSub.broadcast(pubsub, "a", :right_topic)
    assert_receive(:right_topic)
  end

  test "broadcast_from/4 skips the sender" do
    pubsub = start_pubsub()

    :ok = PubSub.subscribe(pubsub, "t")
    :ok = PubSub.broadcast_from(pubsub, self(), "t", :from_elsewhere)

    refute_receive(:from_elsewhere)
  end

  test "broadcast_from/4 still reaches other subscribers" do
    pubsub = start_pubsub()
    me = self()

    worker = start_subscriber(pubsub, "t", me)
    assert_receive(:ready)

    :ok = PubSub.broadcast_from(pubsub, self(), "t", :hello)

    assert_receive({:relay, :hello})
    refute_receive(:hello)

    send(worker, :stop)
  end

  test "unsubscribe/2 stops delivery" do
    pubsub = start_pubsub()

    :ok = PubSub.subscribe(pubsub, "t")
    :ok = PubSub.unsubscribe(pubsub, "t")
    :ok = PubSub.broadcast(pubsub, "t", :gone)

    refute_receive(:gone)
  end

  test "topics/1 returns topics subscribed by the caller" do
    pubsub = start_pubsub()

    assert [] = PubSub.topics(pubsub)

    :ok = PubSub.subscribe(pubsub, "x")
    :ok = PubSub.subscribe(pubsub, "y")
    :ok = PubSub.subscribe(pubsub, "x")

    assert Enum.sort(PubSub.topics(pubsub)) == ["x", "y"]
  end

  test "subscriber_count/2 counts subscribers per topic" do
    pubsub = start_pubsub()
    me = self()

    assert 0 == PubSub.subscriber_count(pubsub, "t")

    :ok = PubSub.subscribe(pubsub, "t")
    assert 1 == PubSub.subscriber_count(pubsub, "t")

    worker = start_subscriber(pubsub, "t", me)
    assert_receive(:ready)
    assert 2 == PubSub.subscriber_count(pubsub, "t")

    send(worker, :stop)
  end
end
