defmodule Dala.Media.AnimationTest do
  use ExUnit.Case, async: false

  alias Dala.Media.Animation

  setup do
    {:ok, pid} = Animation.start_link()
    on_exit(fn -> Process.exit(pid, :kill) end)
    %{pid: pid}
  end

  defp state(pid), do: :sys.get_state(pid)

  test "animate/4 registers an animation with frame duration derived from ms", %{pid: pid} do
    node_id = make_ref()

    assert {:ok, anim_id} =
             Animation.animate(pid, node_id, :opacity, %{
               from: 0.0,
               to: 1.0,
               duration_ms: 500,
               easing: :linear
             })

    anims = state(pid).animations
    assert Map.size(anims) == 1
    anim = Map.get(anims, anim_id)
    # 500ms / 16ms frames → 31 frames (min 1)
    assert anim.duration_frames == div(500, 16)
    assert anim.node_id == node_id
    assert anim.property == :opacity
    assert anim.easing == :linear
    assert anim.active == true
  end

  test "very short durations clamp to a single frame", %{pid: pid} do
    {:ok, anim_id} = Animation.animate(pid, make_ref(), :x, %{from: 0, to: 10, duration_ms: 1})
    assert state(pid).animations[anim_id].duration_frames == 1
  end

  test "missing :from or :to takes the animation server down (fetch!/2 in handle_call)", %{
    pid: pid
  } do
    Process.flag(:trap_exit, true)

    catch_exit(Animation.animate(pid, make_ref(), :x, %{from: 0}))

    refute Process.alive?(pid)
  end

  test "cancel/2 removes the animation", %{pid: pid} do
    {:ok, anim_id} = Animation.animate(pid, make_ref(), :x, %{from: 0, to: 1})

    :ok = Animation.cancel(pid, anim_id)

    refute Map.has_key?(state(pid).animations, anim_id)
  end

  test "cancel_all/2 removes only the given node's animations", %{pid: pid} do
    keep_node = make_ref()
    drop_node = make_ref()

    {:ok, _} = Animation.animate(pid, keep_node, :x, %{from: 0, to: 1})
    {:ok, dropped_a} = Animation.animate(pid, drop_node, :y, %{from: 0, to: 1})
    {:ok, dropped_b} = Animation.animate(pid, drop_node, :z, %{from: 0, to: 1})

    :ok = Animation.cancel_all(pid, drop_node)

    anims = state(pid).animations
    refute Map.has_key?(anims, dropped_a)
    refute Map.has_key?(anims, dropped_b)
    assert map_size(anims) == 1
  end

  test "clock ticks deactivate animations once past their last frame", %{pid: pid} do
    {:ok, anim_id} = Animation.animate(pid, make_ref(), :opacity, %{from: 0.0, to: 1.0})
    frames = state(pid).animations[anim_id].duration_frames

    for frame <- 0..(frames + 1) do
      send(pid, {:clock, :tick, %{frame: frame}})
    end

    Process.sleep(50)
    anim = state(pid).animations[anim_id]
    assert anim.active == false
  end

  test "non-clock messages are ignored", %{pid: pid} do
    send(pid, :something_else)
    Process.sleep(20)
    assert state(pid).animations == %{}
  end
end
