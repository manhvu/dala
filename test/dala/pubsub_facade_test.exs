defmodule Dala.PubSubFacadeTest do
  @moduledoc """
  Exercises every defdelegate in the `Dala.PubSub` facade against a live
  `Dala.Platform.PubSub` instance.
  """

  use ExUnit.Case, async: false

  setup do
    start_supervised!({Dala.PubSub, name: Dala.PubSub.Test})
    :ok
  end

  test "subscribe/broadcast/unsubscribe round trip" do
    :ok = Dala.PubSub.subscribe(Dala.PubSub.Test, "room")

    :ok = Dala.PubSub.broadcast(Dala.PubSub.Test, "room", {:msg, 1})
    assert_received {:msg, 1}

    :ok = Dala.PubSub.unsubscribe(Dala.PubSub.Test, "room")
    :ok = Dala.PubSub.broadcast(Dala.PubSub.Test, "room", {:msg, 2})
    refute_received {:msg, 2}
  end

  test "broadcast_from/4 skips the sender" do
    other = self()

    pid =
      spawn_link(fn ->
        Dala.PubSub.subscribe(Dala.PubSub.Test, "t")

        send(other, :subscribed)

        receive do
          m -> send(other, {:got, m})
        end
      end)

    receive do
      :subscribed -> :ok
    after
      500 -> flunk("subscriber never subscribed")
    end

    # Subscribe AFTER so we're not in the topic; broadcast_from(pid) must not
    # deliver to pid itself but should reach us.
    :ok = Dala.PubSub.subscribe(Dala.PubSub.Test, "t")
    :ok = Dala.PubSub.broadcast_from(Dala.PubSub.Test, self(), "t", :hello)

    assert_receive {:got, :hello}, 500
    refute_received :hello
  end

  test "topics/1 and subscriber_count/2 report state" do
    :ok = Dala.PubSub.subscribe(Dala.PubSub.Test, "a")
    :ok = Dala.PubSub.subscribe(Dala.PubSub.Test, "b")
    :ok = Dala.PubSub.subscribe(Dala.PubSub.Test, "b")

    topics = Dala.PubSub.topics(Dala.PubSub.Test)
    assert MapSet.new(topics) == MapSet.new(["a", "b"])
    assert Dala.PubSub.subscriber_count(Dala.PubSub.Test, "b") == 2
    assert Dala.PubSub.subscriber_count(Dala.PubSub.Test, "missing") == 0
  end

  test "child_spec/1 is provided" do
    spec = Dala.PubSub.child_spec(name: Dala.PubSub.Test)
    assert spec.id == Dala.PubSub.Test
    assert spec.type == :supervisor
  end
end
