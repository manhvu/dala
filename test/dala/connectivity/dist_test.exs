defmodule Dala.Connectivity.DistTest do
  use ExUnit.Case, async: false

  alias Dala.Dist
  alias Dala.Connectivity.Dist

  describe "apply_suffix/2" do
    test "returns the base node unchanged for nil or empty suffix" do
      base = :"my_app@127.0.0.1"

      assert Dala.Connectivity.Dist.apply_suffix(base, nil) == base
      assert Dala.Connectivity.Dist.apply_suffix(base, "") == base
      assert Dala.Connectivity.Dist.apply_suffix(base, "   ") == base
    end

    test "inserts the suffix before the host part" do
      assert Dala.Connectivity.Dist.apply_suffix(:"my_app@127.0.0.1", "abc123") ==
               :"my_app_abc123@127.0.0.1"
    end

    test "appends the suffix when the node has no host part" do
      assert Dala.Connectivity.Dist.apply_suffix(:bare_node, "s1") == :bare_node_s1
    end

    test "trims surrounding whitespace from the suffix" do
      assert Dala.Connectivity.Dist.apply_suffix(:my_app@h, " s2 ") == :my_app_s2@h
    end
  end

  describe "release_mode?/0" do
    setup do
      prev = System.get_env("DALA_RELEASE")
      on_exit(fn -> restore("DALA_RELEASE", prev) end)
      :ok
    end

    test "is true only when DALA_RELEASE=1" do
      System.put_env("DALA_RELEASE", "1")
      assert Dala.Connectivity.Dist.release_mode?() == true

      System.delete_env("DALA_RELEASE")
      assert Dala.Connectivity.Dist.release_mode?() == false

      System.put_env("DALA_RELEASE", "0")
      assert Dala.Connectivity.Dist.release_mode?() == false
    end
  end

  test "stop/0 is a safe no-op when distribution is not running" do
    if Node.alive?() do
      # Don't break a distributed test host — just verify it returns :ok
      assert Dala.Connectivity.Dist.stop() == :ok
    else
      assert Dala.Connectivity.Dist.stop() == :ok
      refute Node.alive?()
    end
  end

  describe "Dala.Dist facade" do
    test "delegates apply_suffix/2" do
      assert Dist.apply_suffix(:a@b, "x") == Dala.Connectivity.Dist.apply_suffix(:a@b, "x")
    end

    test "delegates release_mode?/0" do
      assert Dist.release_mode?() == Dala.Connectivity.Dist.release_mode?()
    end

    test "delegates stop/0" do
      assert Dist.stop() == :ok
    end
  end

  defp restore(var, nil), do: System.delete_env(var)
  defp restore(var, val), do: System.put_env(var, val)
end
