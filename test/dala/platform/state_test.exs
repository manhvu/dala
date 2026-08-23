defmodule Dala.Platform.StateTest do
  use ExUnit.Case, async: false

  alias Dala.Platform.State

  setup do
    dir = Path.join(System.tmp_dir!(), "dala_state_test_#{System.unique_integer([:positive])}")
    prev = System.get_env("dala_DATA_DIR")
    System.put_env("dala_DATA_DIR", dir)

    on_exit(fn ->
      case Process.whereis(State) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      restore_env("dala_DATA_DIR", prev)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  defp restore_env(_var, nil), do: System.delete_env("dala_DATA_DIR")
  defp restore_env(var, val), do: System.put_env(var, val)

  # restart: :temporary so a mid-test GenServer.stop isn't undone by an
  # automatic supervisor restart racing with our manual restart below.
  defp start_state, do: start_supervised!(State, restart: :temporary)

  test "get/2 returns nil by default and explicit default when set" do
    start_state()

    assert State.get(:missing) == nil
    assert State.get(:missing, :fallback) == :fallback
  end

  test "put/2 then get/2 round-trips any term" do
    start_state()

    :ok = State.put(:theme, :citrus)
    :ok = State.put(:count, 42)
    :ok = State.put(:prefs, %{font_size: 16, tags: [:a, :b]})
    :ok = State.put({:compound, :key}, [1, 2, 3])

    assert State.get(:theme) == :citrus
    assert State.get(:count) == 42
    assert State.get(:prefs) == %{font_size: 16, tags: [:a, :b]}
    assert State.get({:compound, :key}) == [1, 2, 3]
  end

  test "put/2 overwrites an existing key" do
    start_state()

    :ok = State.put(:key, :old)
    :ok = State.put(:key, :new)

    assert State.get(:key) == :new
  end

  test "delete/1 removes a key and is a no-op when absent" do
    start_state()

    :ok = State.put(:key, :value)
    :ok = State.delete(:key)
    assert State.get(:key, :default) == :default

    assert State.delete(:never_existed) == :ok
  end

  test "values survive a full stop/restart cycle" do
    start_state()
    :ok = State.put(:persistent, %{survives: true})
    :ok = State.put(:gone, true)
    :ok = State.delete(:gone)

    GenServer.stop(State)
    refute Process.whereis(State)

    {:ok, _} = State.start_link()

    assert State.get(:persistent) == %{survives: true}
    assert State.get(:gone, false) == false
  end

  test "backing file is created inside dala_DATA_DIR", %{dir: dir} do
    start_state()
    :ok = State.put(:bootstraps_file, true)

    assert File.exists?(Path.join(dir, "dala_state.dets"))
  end
end
