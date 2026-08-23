defmodule Dala.Diff do
  @moduledoc """
  Diff engine for incremental UI updates.

  Compares two UI trees (as `Dala.Node` structs) and produces a minimal
  set of patches to transform the old tree into the new tree.

  ## Patch format

  Patches are tuples tagged with an action:

      {:replace, id, node}           # Replace entire node
      {:update_props, id, props}     # Update props on existing node (full replacement)
      {:patch_node, id, mask, props}  # Patch only changed fields (field-mask based)
      {:insert, parent_id, index, node}  # Insert new node
      {:remove, id}                  # Remove node

  ## Usage

      old_tree = Dala.Node.from_map(old_map, "root")
      new_tree = Dala.Node.from_map(new_map, "root")
      patches = Dala.Diff.diff(old_tree, new_tree)

  ## Node identity

  Nodes are identified by the `:id` field in `Dala.Node`. This must be
  stable across renders for proper reconciliation.

  ## Field masks

  When only a few props change, `{:patch_node, id, mask, props}` is emitted
  instead of `{:update_props, id, props}`. The mask is a 16-bit bitmask
  where bit N corresponds to field tag (N+1). If more than half the fields
  changed, a full `{:update_props, ...}` is sent instead.
  """

  alias Dala.Ui.Diff

  @type node_id :: String.t() | atom()

  @type patch ::
          {:replace, node_id(), Dala.Node.t()}
          | {:update_props, node_id(), map()}
          | {:patch_node, node_id(), non_neg_integer(), map()}
          | {:insert, node_id(), non_neg_integer(), Dala.Node.t()}
          | {:remove, node_id()}

  @doc """
  Compute the diff between two UI trees.

  Returns a list of patches to transform `old_tree` into `new_tree`.
  """
  @spec diff(Dala.Node.t() | map() | nil, Dala.Node.t() | map() | nil) :: [patch()]
  def diff(nil, nil), do: []
  def diff(nil, %Dala.Node{} = new), do: Diff.diff(nil, new)
  def diff(nil, %{} = new_map), do: Diff.diff(nil, new_map)
  def diff(%Dala.Node{} = old, nil), do: Diff.diff(old, nil)
  def diff(%{} = old_map, nil), do: Diff.diff(old_map, nil)
  def diff(%Dala.Node{} = old, %Dala.Node{} = new), do: Diff.diff(old, new)
  def diff(%Dala.Node{} = old, %{} = new_map), do: Diff.diff(old, new_map)
  def diff(%{} = old_map, %Dala.Node{} = new), do: Diff.diff(old_map, new)
  def diff(%{} = old_map, %{} = new_map), do: Diff.diff(old_map, new_map)

  @doc """
  Compute a field mask and changed props map from old and new props.

  Delegates to `Dala.Ui.Diff.compute_field_mask/2`.
  """
  @spec compute_field_mask(map(), map()) :: {non_neg_integer(), map()}
  defdelegate compute_field_mask(old_props, new_props), to: Diff
end
