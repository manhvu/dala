defmodule Dala.DiffFacadeTest do
  @moduledoc """
  Covers the `Dala.Diff` facade's delegation clauses (struct/map/nil mixes).
  The underlying algorithm is exercised in `Dala.DiffTest` via `Dala.Ui.Diff`.
  """

  use ExUnit.Case, async: true

  defp node_map(id, text) do
    %{type: :text, id: id, props: %{text: text}, children: []}
  end

  defp struct_node(id, text) do
    Dala.Node.from_map(node_map(id, text), "root")
  end

  test "diff(nil, nil) is empty" do
    assert Dala.Diff.diff(nil, nil) == []
  end

  test "nil old tree produces replace patches for every new root" do
    new = struct_node("root", "hello")

    patches = Dala.Diff.diff(nil, new)
    assert patches != []
  end

  test "nil new tree removes the old roots" do
    old = struct_node("root", "bye")
    assert Dala.Diff.diff(old, nil) != []
  end

  test "struct vs map mixes work in both directions" do
    old = struct_node("root", "a")
    new_map = node_map("root", "b")

    assert Dala.Diff.diff(old, new_map) != []

    assert Dala.Diff.diff(%{type: :column, props: %{}, children: []}, struct_node("root", "x")) !=
             []
  end

  test "identical trees (any representation) produce no patches" do
    map = node_map("root", "same")

    assert Dala.Diff.diff(map, map) == []
    assert Dala.Diff.diff(struct_node("root", "same"), struct_node("root", "same")) == []
  end

  test "compute_field_mask delegates and reports changed props" do
    {mask, changed} = Dala.Diff.compute_field_mask(%{text: "a"}, %{text: "b"})
    assert mask > 0
    assert changed != %{}
  end

  test "compute_field_mask with equal props yields zero mask" do
    {mask, changed} = Dala.Diff.compute_field_mask(%{text: "a"}, %{text: "a"})
    assert mask == 0
    assert changed == %{}
  end

  test "Node structs and plain maps diff to the same result" do
    a = Dala.Diff.diff(node_map("r", "x"), node_map("r", "y"))
    b = Dala.Diff.diff(struct_node("r", "x"), struct_node("r", "y"))
    assert a == b
  end
end
