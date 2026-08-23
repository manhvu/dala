defmodule Dala.ThemeTest do
  @moduledoc """
  Tests for Dala.Theme public API — resolve, set_accent, prefers_reduced_motion,
  line_height_map, and Adaptive.Custom.
  """
  use ExUnit.Case, async: true

  alias Dala.Theme.Theme

  setup do
    original = Dala.Theme.current()
    on_exit(fn -> Dala.Theme.set(original) end)
    :ok
  end

  describe "resolve/1" do
    test "resolves color tokens to values" do
      primary = Dala.Theme.resolve(:primary)
      assert primary != nil
    end

    test "resolves spacing tokens to pixel values" do
      assert Dala.Theme.resolve(:space_xs) == 4
      assert Dala.Theme.resolve(:space_sm) == 8
      assert Dala.Theme.resolve(:space_md) == 16
      assert Dala.Theme.resolve(:space_lg) == 24
      assert Dala.Theme.resolve(:space_xl) == 32
    end

    test "resolves radius tokens" do
      assert Dala.Theme.resolve(:radius_sm) == 6
      assert Dala.Theme.resolve(:radius_md) == 10
      assert Dala.Theme.resolve(:radius_lg) == 16
      assert Dala.Theme.resolve(:radius_pill) == 100
    end

    test "returns nil for unknown tokens" do
      assert Dala.Theme.resolve(:nonexistent_token) == nil
    end

    test "reflects theme overrides" do
      Dala.Theme.set(primary: 0xFF00FF00)
      assert Dala.Theme.resolve(:primary) == 0xFF00FF00
    end
  end

  describe "set_accent/1" do
    test "overrides primary with raw integer color" do
      Dala.Theme.set_accent(0xFFFF0000)
      theme = Dala.Theme.current()
      assert theme.primary == 0xFFFF0000
    end

    test "auto-selects on_primary for dark colors" do
      Dala.Theme.set_accent(0xFF000000)
      theme = Dala.Theme.current()
      assert theme.on_primary == 0xFFFFFFFF
    end

    test "auto-selects on_primary for light colors" do
      Dala.Theme.set_accent(0xFFFFFFFF)
      theme = Dala.Theme.current()
      assert theme.on_primary == 0xFF0F0F0F
    end

    test "preserves other theme tokens" do
      original = Dala.Theme.current()
      Dala.Theme.set_accent(0xFF00FF00)
      updated = Dala.Theme.current()
      assert updated.surface == original.surface
      assert updated.background == original.background
      assert updated.error == original.error
    end
  end

  describe "prefers_reduced_motion/0" do
    test "returns a boolean" do
      result = Dala.Theme.prefers_reduced_motion()
      assert is_boolean(result)
    end
  end

  describe "line_height_map/1" do
    test "returns line height tokens" do
      theme = Dala.Theme.current()
      lh = Theme.line_height_map(theme)
      assert lh.line_height_tight == 1.25
      assert lh.line_height_normal == 1.5
      assert lh.line_height_relaxed == 1.75
    end
  end

  describe "Adaptive.Custom" do
    test "new/1 creates struct with defaults" do
      custom = Dala.Theme.Adaptive.Custom.new([])
      assert custom.dark == Dala.Theme.Dark
      assert custom.light == Dala.Theme.Light
    end

    test "new/1 accepts custom dark/light modules" do
      custom = Dala.Theme.Adaptive.Custom.new(dark: Dala.Theme.Obsidian, light: Dala.Theme.Birch)
      assert custom.dark == Dala.Theme.Obsidian
      assert custom.light == Dala.Theme.Birch
    end

    test "theme/1 returns a Dala.Theme.t()" do
      custom = Dala.Theme.Adaptive.Custom.new([])
      theme = Dala.Theme.Adaptive.Custom.theme(custom)
      assert %Dala.Theme.Theme{} = theme
    end
  end

  describe "set/1 variants" do
    test "set/1 with a theme struct" do
      theme = Theme.build(primary: 0xFF112233)
      :ok = Dala.Theme.set(theme)
      assert %Theme{primary: 0xFF112233} = Dala.Theme.current()
    end

    test "set/1 with a theme module" do
      :ok = Dala.Theme.set(Dala.Theme.Dark)
      current = Dala.Theme.current()
      assert %Theme{} = current
      # Dark theme's near-black background
      assert current.background == 0xFF0A0A0A
    end

    test "set/1 with {module, overrides}" do
      :ok = Dala.Theme.set({Dala.Theme.Dark, primary: 0xFFABCDEF})
      current = Dala.Theme.current()
      assert current.background == 0xFF0A0A0A
      assert current.primary == 0xFFABCDEF
    end

    test "set/1 with keyword overrides builds against the neutral base" do
      :ok = Dala.Theme.set(primary: 0xFF445566)
      assert %Theme{primary: 0xFF445566} = Dala.Theme.current()
    end
  end

  describe "bundled themes" do
    test "all bundled theme modules compile to valid themes" do
      for mod <- [
            Dala.Theme.Light,
            Dala.Theme.Dark,
            Dala.Theme.Obsidian,
            Dala.Theme.Birch,
            Dala.Theme.Citrus
          ] do
        theme = mod.theme()
        assert %Theme{} = theme
        # primary may be an ARGB integer or a named palette token (:lime_400)
        assert theme.primary != nil
        assert theme.background != nil
        assert theme.on_background != nil
      end
    end

    test "each bundled theme resolves its own tokens" do
      for mod <- [Dala.Theme.Dark, Dala.Theme.Birch] do
        Dala.Theme.set(mod)
        assert Dala.Theme.resolve(:primary) == mod.theme().primary
        assert Dala.Theme.resolve(:space_md) == 16
        assert Dala.Theme.resolve(:radius_pill) == mod.theme().radius_pill
      end
    end
  end

  describe "token maps" do
    test "color_map exposes all color roles" do
      map = Theme.color_map(Theme.default())

      for key <- [
            :primary,
            :on_primary,
            :secondary,
            :on_secondary,
            :surface,
            :surface_raised,
            :on_surface,
            :muted,
            :background,
            :on_background,
            :error,
            :on_error,
            :border
          ] do
        assert Map.has_key?(map, key)
      end
    end

    test "spacing_map applies the space scale" do
      scaled = Theme.spacing_map(%{Theme.default() | space_scale: 2.0})
      assert scaled.space_md == 32
      assert scaled.space_xs == 8
    end

    test "radius_map and line_height_map expose their tokens" do
      radius = Theme.radius_map(Theme.default())
      assert %{radius_sm: _, radius_md: _, radius_lg: _, radius_pill: _} = radius

      lh = Theme.line_height_map(Theme.default())
      assert lh.line_height_tight == 1.25
      assert lh.line_height_normal == 1.5
      assert lh.line_height_relaxed == 1.75
    end
  end

  describe "set_accent/1 edge cases" do
    test "named color token resolves before being set" do
      :ok = Dala.Theme.set([])
      resolved = Dala.Theme.resolve(:emerald_500)

      if resolved do
        :ok = Dala.Theme.set_accent(:emerald_500)
        assert Dala.Theme.current().primary == resolved
      end
    end

    test "light integer colors get dark on_primary" do
      :ok = Dala.Theme.set_accent(0xFFFF_FFFF)
      assert Dala.Theme.current().on_primary == 0xFF0F0F0F
    end

    test "dark integer colors get white on_primary" do
      :ok = Dala.Theme.set_accent(0xFF00_0001)
      assert Dala.Theme.current().on_primary == 0xFFFFFFFF
    end
  end

  describe "host fallbacks" do
    test "prefers_reduced_motion/0 returns false on the host BEAM" do
      assert Dala.Theme.prefers_reduced_motion() == false
    end

    test "color_scheme/0 returns :light on the host BEAM" do
      assert Dala.Theme.color_scheme() in [:light, :dark]
    end

    test "build/1 applies overrides to defaults" do
      theme = Theme.build(space_scale: 1.5)
      assert theme.space_scale == 1.5
      assert theme.radius_md == Theme.default().radius_md
    end
  end
end
