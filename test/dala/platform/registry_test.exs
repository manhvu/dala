defmodule Dala.Platform.RegistryTest do
  use ExUnit.Case, async: true

  alias Dala.Platform.Registry

  defp unique_name do
    :"dala_registry_test_#{System.unique_integer([:positive])}"
  end

  test "start_link/0 starts the registry pre-populated with builtins" do
    name = unique_name()
    {:ok, pid} = Registry.start_link(name: name)

    assert Enum.sort(Registry.all(pid)) == [:button, :column, :row, :scroll, :text]
    assert {:ok, {Dala.Platform.Native, :create_label, []}} = Registry.lookup(pid, :text, :ios)

    assert {:ok, {Dala.Platform.Native, :create_button, []}} =
             Registry.lookup(pid, :button, :android)
  end

  test "start_link/1 supports anonymous registries" do
    {:ok, pid} = Registry.start_link(name: nil)

    assert is_pid(pid)
    # Builtins are seeded for anonymous instances too
    assert :text in Registry.all(pid)
  end

  test "register/3 adds a component per platform" do
    {:ok, pid} = Registry.start_link(name: nil)

    :ok =
      Registry.register(pid, :map_view,
        ios: {MyNative, :create_map, []},
        android: {MyNative, :create_map_android, []}
      )

    assert {:ok, {MyNative, :create_map, []}} = Registry.lookup(pid, :map_view, :ios)
    assert {:ok, {MyNative, :create_map_android, []}} = Registry.lookup(pid, :map_view, :android)
    assert {:error, :not_found} = Registry.lookup(pid, :map_view, :web)
  end

  test "register/3 merges platforms and overwrites existing entries" do
    {:ok, pid} = Registry.start_link(name: nil)

    :ok = Registry.register(pid, :chart, ios: {ChartV1, :make, []})
    :ok = Registry.register(pid, :chart, ios: {ChartV2, :make, []}, web: {ChartV2, :web, []})

    assert {:ok, {ChartV2, :make, []}} = Registry.lookup(pid, :chart, :ios)
    assert {:ok, {ChartV2, :web, []}} = Registry.lookup(pid, :chart, :web)
  end

  test "lookup/3 returns not_found for unknown components" do
    {:ok, pid} = Registry.start_link(name: nil)

    assert {:error, :not_found} = Registry.lookup(pid, :nope, :ios)
  end

  test "all/1 lists registered component names" do
    {:ok, pid} = Registry.start_link(name: nil)

    :ok = Registry.register(pid, :b, ios: {M, :f, []})
    :ok = Registry.register(pid, :a, ios: {M, :f, []})

    assert Enum.sort(Registry.all(pid)) ==
             Enum.sort([:a, :b | Map.keys(builtins())])
  end

  defp builtins do
    %{
      column: %{ios: {Dala.Platform.Native, :create_column, []}},
      row: %{ios: {Dala.Platform.Native, :create_row, []}},
      text: %{ios: {Dala.Platform.Native, :create_label, []}},
      button: %{ios: {Dala.Platform.Native, :create_button, []}},
      scroll: %{ios: {Dala.Platform.Native, :create_scroll, []}}
    }
  end
end
