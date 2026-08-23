defmodule Dala.Renderer do
  @moduledoc """
  Serializes a component tree to a binary command stream and passes it to the
  platform NIF in a single call. Compose (Android) and SwiftUI (iOS) handle
  diffing and rendering internally.

  ## Node format

      %{
        type: :column,
        props: %{padding: :space_md, background: :surface},
        children: [
          %{type: :text,   props: %{text: "Hello", text_size: :xl, text_color: :on_surface}, children: []},
          %{type: :button, props: %{text: "Tap", on_tap: self()},    children: []}
        ]
      }

  ## Token resolution

  Atom values for color props, spacing props, radius props, and text sizes are
  resolved at render time through the active `Dala.Theme` and the base palette.

  ## Component defaults

  When a component's props omit styling keys, the renderer injects sensible
  defaults from the active theme. Explicit props always win over defaults.

  ## Platform blocks

  Props scoped to one platform are silently ignored on the other:

      props: %{padding: 12, ios: %{padding: 20}}
      # iOS sees padding: 20; Android sees padding: 12

  ## Injecting a mock NIF

      Dala.Renderer.render(tree, :android, MockNIF)

  ## Binary protocol

  See `Dala.Renderer` module docs and `guides/binary_protocol.md` for the full
  binary protocol specification (v3).
  """

  alias Dala.Ui.Renderer

  @default_nif Dala.Platform.Native

  @doc """
  Render a UI tree for the given platform.
  """
  @spec render(Dala.Node.t() | map(), atom(), term(), atom()) ::
          {:ok, :binary_tree} | {:error, term()}
  def render(tree, platform, nif \\ @default_nif, transition \\ :none)

  def render(%Dala.Node{} = tree, platform, nif, transition) do
    Renderer.render(tree, platform, nif, transition)
  end

  def render(tree, platform, nif, transition) when is_map(tree) do
    Renderer.render(tree, platform, nif, transition)
  end

  @doc """
  Fast render path for simple updates.
  """
  @spec render_fast(Dala.Node.t() | map(), atom(), term(), atom()) ::
          {:ok, :binary_tree} | {:error, term()}
  def render_fast(tree, platform, nif \\ @default_nif, transition \\ :none)

  def render_fast(%Dala.Node{} = tree, platform, nif, transition) do
    Renderer.render_fast(tree, platform, nif, transition)
  end

  def render_fast(tree, platform, nif, transition) when is_map(tree) do
    Renderer.render_fast(tree, platform, nif, transition)
  end

  @doc """
  Compute patches between old and new trees.
  """
  @spec render_patches(Dala.Node.t() | map() | nil, Dala.Node.t() | map(), atom(), term(), atom()) ::
          {:ok, [Dala.Diff.patch()]} | {:error, term()}
  def render_patches(old_tree, new_tree, platform, nif \\ @default_nif, transition \\ :none)

  def render_patches(old_tree, new_tree, platform, nif, transition) do
    Renderer.render_patches(old_tree, new_tree, platform, nif, transition)
  end

  @doc """
  Encode patches to binary frame format for the native side.
  """
  @spec encode_frame([Dala.Diff.patch()]) :: binary()
  defdelegate encode_frame(patches), to: Renderer

  @doc """
  Get available colors from theme.
  """
  @spec colors() :: map()
  defdelegate colors(), to: Renderer

  @doc """
  Get text sizes from theme.
  """
  @spec text_sizes() :: map()
  defdelegate text_sizes(), to: Renderer

  @doc """
  Encode a targeted text update for an existing node.

  Delegates to `Dala.Ui.Renderer.encode_set_text/2`.
  """
  @spec encode_set_text(String.t(), String.t()) :: binary()
  defdelegate encode_set_text(id, text), to: Renderer

  @doc """
  Encode a string-table registration entry.

  Delegates to `Dala.Ui.Renderer.encode_register_string/2`.
  """
  @spec encode_register_string(non_neg_integer(), String.t()) :: binary()
  defdelegate encode_register_string(string_id, text), to: Renderer

  @doc """
  Encode a native event frame.

  Delegates to `Dala.Ui.Renderer.encode_event/4`.
  """
  @spec encode_event(String.t(), non_neg_integer(), non_neg_integer(), binary()) :: binary()
  defdelegate encode_event(target_id, event_type, timestamp, payload), to: Renderer

  @doc """
  Encode a field-mask node patch frame.

  Delegates to `Dala.Ui.Renderer.encode_patch_node/3`.
  """
  @spec encode_patch_node(String.t(), non_neg_integer(), map()) :: binary()
  defdelegate encode_patch_node(id, field_mask, changed_props), to: Renderer

  @doc """
  Compute a stable layout hash for a node tree.

  Delegates to `Dala.Ui.Renderer.compute_layout_hash/1`.
  """
  @spec compute_layout_hash(Dala.Node.t()) :: non_neg_integer()
  defdelegate compute_layout_hash(node), to: Renderer
end
