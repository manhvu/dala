defmodule Dala.Ui.Widgets do
  @moduledoc """
  UI component constructors for the Dala framework.

  Each function returns a node map compatible with `Dala.Ui.Renderer`. These can
  be used directly or mixed freely — they produce the same map format.

      # Native map literal
      %{type: :text, props: %{text: "Hello"}, children: []}

      # Component function (keyword list or map)
      Dala.Ui.Widgets.text(text: "Hello")

  Both forms produce identical output and are accepted by `Dala.Ui.Renderer`.
  """

  # ── Shared prop sets ──────────────────────────────────────────────────────
  # These are used by Map.take to filter props, keeping the serialised tree
  # clean and avoiding typos silently swallowed.

  @typography_props [
    :text,
    :text_color,
    :text_size,
    :font_weight,
    :font_family,
    :text_align,
    :italic,
    :line_height,
    :letter_spacing,
    :variant,
    :selectable
  ]

  @layout_props [
    :padding,
    :padding_top,
    :padding_right,
    :padding_bottom,
    :padding_left,
    :gap,
    :background,
    :border_color,
    :border_width,
    :corner_radius,
    :fill_width,
    :width,
    :height
  ]

  @gesture_props [
    :on_tap,
    :on_long_press,
    :on_double_tap,
    :on_swipe,
    :on_swipe_left,
    :on_swipe_right,
    :on_swipe_up,
    :on_swipe_down
  ]

  @accessibility_props [
    :accessibility_id,
    :accessibility_label,
    :accessibility_hint,
    :accessibility_role,
    :accessibility_value,
    :accessibility_hidden
  ]

  # ── Layout containers ─────────────────────────────────────────────────────

  @doc """
  Returns a `:column` container node. Children are laid out vertically (VStack).

  ## Props

    * `:gap` — spacing between children (accepts spacing tokens like `:space_md`)
    * `:padding`, `:padding_top`, `:padding_right`, `:padding_bottom`, `:padding_left`
    * `:background` — background color (accepts color tokens)
    * `:border_color`, `:border_width` — optional border
    * `:corner_radius` — rounded corners
    * `:fill_width` — boolean, stretch to fill parent width
    * `:on_tap`, `:on_long_press`, `:on_double_tap`, `:on_swipe*` — gesture handlers
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.column([padding: :space_md, gap: :space_sm], [
        Dala.Ui.Widgets.text(text: "Title"),
        Dala.Ui.Widgets.text(text: "Subtitle")
      ])
  """
  @spec column(keyword() | map(), list()) :: map()
  def column(props, children \\ [])
  def column(props, children) when is_list(props), do: column(Map.new(props), children)

  def column(%{} = props, children) when is_list(children) do
    # Map friendly names to binary-protocol names
    props =
      props
      |> Map.put_new(:align_items, props[:alignment])
      |> Map.put_new(:justify_content, props[:justify])
      |> Enum.filter(fn {_k, v} -> v != nil end)
      |> Map.new()

    allowed =
      @layout_props ++
        @gesture_props ++
        @accessibility_props ++ [:align_items, :justify_content, :alignment, :justify]

    %{
      type: :column,
      props: Map.take(props, allowed),
      children: children
    }
  end

  @doc """
  Returns a `:row` container node. Children are laid out horizontally (HStack).

  Same props as `column/2`.
  """
  @spec row(keyword() | map(), list()) :: map()
  def row(props, children \\ [])
  def row(props, children) when is_list(props), do: row(Map.new(props), children)

  def row(%{} = props, children) when is_list(children) do
    # Map friendly names to binary-protocol names
    props =
      props
      |> Map.put_new(:align_items, props[:alignment])
      |> Map.put_new(:justify_content, props[:justify])
      |> Enum.filter(fn {_k, v} -> v != nil end)
      |> Map.new()

    allowed =
      @layout_props ++
        @gesture_props ++
        @accessibility_props ++ [:align_items, :justify_content, :alignment, :justify]

    %{
      type: :row,
      props: Map.take(props, allowed),
      children: children
    }
  end

  @doc """
  Returns a `:box` container node. Children are stacked on top of each other (ZStack).

  Same props as `column/2`. Useful for overlays, badges, and absolute positioning.
  """
  @spec box(keyword() | map(), list()) :: map()
  def box(props, children \\ [])
  def box(props, children) when is_list(props), do: box(Map.new(props), children)

  def box(%{} = props, children) when is_list(children) do
    allowed = @layout_props ++ @gesture_props ++ @accessibility_props

    %{
      type: :box,
      props: Map.take(props, allowed),
      children: children
    }
  end

  # ── Leaf nodes ────────────────────────────────────────────────────────────

  @doc """
  Returns a `:text` leaf node.

  ## Props

    * `:text` — the string to display (required)
    * `:text_color` — color value (accepts color tokens like `:on_surface`)
    * `:text_size` — font size (accepts size tokens like `:xl` or numeric sp)
    * `:font_weight` — `"regular"`, `"medium"`, `"semibold"`, `"bold"`, `"light"`, `"thin"`
    * `:font_family` — custom font family name (nil = system font)
    * `:text_align` — `:left`, `:center`, `:right`
    * `:italic` — boolean
    * `:line_height` — multiplier (e.g. `1.5` for 150% line height)
    * `:letter_spacing` — extra spacing in pt
    * `:variant` — text style preset. One of:
      - `:display`   — text_size: :"4xl", font_weight: "bold"
      - `:heading`   — text_size: :"2xl", font_weight: "semibold"
      - `:title`     — text_size: :xl, font_weight: "medium"
      - `:body`      — text_size: :base, font_weight: "regular"
      - `:caption`   — text_size: :sm, text_color: :muted
      - `:label`     — text_size: :xs, font_weight: "medium", text_color: :muted
      - `:overline`  — text_size: :xs, font_weight: "medium"
      When provided, variant sets defaults that individual props override.
    * `:selectable` — boolean, whether the user can select/copy the text (default: false)
    * `:padding`, `:padding_top`, `:padding_right`, `:padding_bottom`, `:padding_left`
    * `:background` — background color
    * `:corner_radius` — rounded corners
    * `:fill_width` — boolean, stretch to fill parent width
    * `:on_tap`, `:on_long_press`, `:on_double_tap` — gesture handlers
    * `:accessibility_id` — test identifier
    * `:accessibility_label` — accessibility label
    * `:accessibility_hint` — accessibility hint
    * `:accessibility_role` — accessibility role
    * `:accessibility_value` — accessibility value
    * `:accessibility_hidden` — hide from accessibility tree

  ## Examples

      Dala.Ui.Widgets.text(text: "Hello")
      Dala.Ui.Widgets.text(text: "Title", text_size: :xl, font_weight: "bold", text_color: :on_surface)
  """
  @spec text(keyword() | map()) :: map()
  def text(props) when is_list(props), do: text(Map.new(props))

  def text(%{} = props) do
    props = apply_variant_defaults(props)
    allowed = @typography_props ++ @layout_props ++ @gesture_props ++ @accessibility_props

    %{
      type: :text,
      props: Map.take(props, allowed),
      children: []
    }
  end

  @variant_defaults %{
    display: [text_size: :"4xl", font_weight: "bold"],
    heading: [text_size: :"2xl", font_weight: "semibold"],
    title: [text_size: :xl, font_weight: "medium"],
    body: [text_size: :base, font_weight: "regular"],
    caption: [text_size: :sm, text_color: :muted],
    label: [text_size: :xs, font_weight: "medium", text_color: :muted],
    overline: [text_size: :xs, font_weight: "medium"]
  }

  @doc """
  The variant preset map (`variant => default props`) used by `apply_variant_defaults/1`.

  Single source of truth for valid `variant:` values — compile-time DSL
  verification derives its accepted variants from this so the two can't drift.
  """
  @spec variant_presets() :: %{atom() => keyword()}
  def variant_presets, do: @variant_defaults

  defp apply_variant_defaults(%{variant: variant} = props) when is_atom(variant) do
    defaults = Map.get(@variant_defaults, variant, [])

    Keyword.merge(defaults, Map.to_list(props))
    |> Map.new()
    |> Map.put(:variant, variant)
  end

  defp apply_variant_defaults(props), do: props

  @doc """
  Returns a `:button` leaf node.

  ## Props

    * `:text` — button label (required). Also accepts `:title` for backward compatibility.
    * `:on_tap` — `{pid, tag}` tuple; fired when button is pressed
    * `:disabled` — boolean, disables the button (default: false)
    * `:text_color` — label color (accepts color tokens)
    * `:text_size` — font size
    * `:font_weight` — `"regular"`, `"medium"`, `"semibold"`, `"bold"`, `"light"`, `"thin"`
    * `:background` — button background color (accepts color tokens)
    * `:padding`, `:padding_top`, `:padding_right`, `:padding_bottom`, `:padding_left`
    * `:corner_radius` — rounded corners
    * `:fill_width` — boolean, stretch to fill parent width (default: true from component defaults)
    * `:accessibility_id` — test identifier
    * `:accessibility_label` — accessibility label
    * `:accessibility_hint` — accessibility hint
    * `:accessibility_role` — accessibility role
    * `:accessibility_value` — accessibility value
    * `:accessibility_hidden` — hide from accessibility tree

  ## Examples

      Dala.Ui.Widgets.button(text: "Submit", on_tap: {self(), :submit})
      Dala.Ui.Widgets.button(title: "OK", on_tap: {self(), :ok}, background: :primary)
  """
  @spec button(keyword() | map()) :: map()
  def button(props \\ [])
  def button(props) when is_list(props), do: button(Map.new(props))

  def button(%{} = props) do
    # Backward compat: :title maps to :text (native side uses node.text)
    props = Map.put_new(props, :text, props[:title])

    allowed =
      [:text, :on_tap, :disabled] ++
        [:text_color, :text_size, :font_weight] ++
        [:background, :padding, :padding_top, :padding_right, :padding_bottom, :padding_left] ++
        [:corner_radius, :fill_width, :accessibility_id] ++
        [:variant, :icon, :elevation]

    %{
      type: :button,
      props: Map.take(props, allowed),
      children: []
    }
  end

  @doc """
  Returns an `:icon` leaf node. Displays a platform-native icon.

  Logical icon names are resolved to SF Symbols on iOS and Material Symbols on
  Android. Unknown names pass through verbatim (power users can use raw SF Symbol
  identifiers like `"globe.americas.fill"`).

  ## Props

    * `:name` — logical icon name or raw identifier (required)
    * `:text_size` — glyph size in sp
    * `:text_color` — glyph tint color (accepts color tokens)
    * `:padding`, `:background` — layout props
    * `:on_tap`, `:on_long_press` — gesture handlers
    * `:accessibility_id` — test identifier (also used as accessibility label)
    * `:accessibility_label` — accessibility label
    * `:accessibility_hint` — accessibility hint
    * `:accessibility_role` — accessibility role
    * `:accessibility_value` — accessibility value
    * `:accessibility_hidden` — hide from accessibility tree

  ## Logical icon names

  `settings`, `back`, `forward`, `close`, `add`, `remove`, `edit`, `check`,
  `chevron_right`, `chevron_left`, `chevron_up`, `chevron_down`, `info`,
  `warning`, `error`, `search`, `trash`, `share`, `more`, `menu`, `refresh`,
  `favorite`, `favorite_filled`, `star`, `star_filled`, `user`, `home`,
  `bookmark`, `bookmark_filled`, `download`, `upload`, `attach`, `camera`,
  `photo`, `notification`, `notification_filled`, `calendar`, `clock`,
  `filter`, `sort`, `grid`, `list`, `lock`, `unlock`, `eye`, `eye_off`,
  `link`, `copy`, `send`, `play`, `pause`, `stop`, `volume`, `volume_off`,
  `mic`, `mic_off`, `call`, `mail`, `location`, `map`, `compass`,
  `flashlight`, `flashlight_off`, `qr_code`, `barcode`, `print`, `cloud`,
  `cloud_off`, `wifi`, `wifi_off`, `bluetooth`, `battery`, `thermometer`,
  `brightness`, `contrast`, `saturation`, `crop`, `rotate`, `flip`, `undo`,
  `redo`, `save`, `folder`, `file`, `document`, `clipboard`, `key`, `shield`,
  `flag`, `tag`, `label`, `bookmark_add`, `bookmark_remove`, `pin`, `unpin`,
  `zoom_in`, `zoom_out`, `fullscreen`, `fullscreen_exit`, `expand`, `collapse`,
  `maximize`, `minimize`

  ## Examples

      Dala.Ui.Widgets.icon(name: "settings", text_size: 24, text_color: :on_surface)
      Dala.Ui.Widgets.icon(name: "chevron_right", on_tap: {self(), :navigate})
  """
  @spec icon(keyword() | map()) :: map()
  def icon(props \\ [])
  def icon(props) when is_list(props), do: icon(Map.new(props))

  def icon(%{} = props) do
    allowed =
      [:name, :text_size, :text_color] ++
        [:padding, :background] ++
        [:on_tap, :on_long_press] ++
        @accessibility_props

    %{
      type: :icon,
      props: Map.take(props, allowed),
      children: []
    }
  end

  @doc """
  Returns a `:divider` leaf node. A horizontal or vertical divider line.

  ## Props

    * `:thickness` — line thickness in pt (default: 1.0)
    * `:color` — divider color (accepts color tokens, default: `:border`)
    * `:padding` — padding around the divider

  ## Examples

      Dala.Ui.Widgets.divider()
      Dala.Ui.Widgets.divider(thickness: 2, color: :primary)
  """
  @spec divider(keyword() | map()) :: map()
  def divider(props \\ [])
  def divider(props) when is_list(props), do: divider(Map.new(props))

  def divider(%{} = props) do
    props =
      case props do
        %{thickness: t} when is_number(t) -> %{props | thickness: t / 1}
        _ -> props
      end

    %{
      type: :divider,
      props: Map.take(props, [:thickness, :color, :padding]),
      children: []
    }
  end

  @doc """
  Returns an `:empty_state` leaf node. Placeholder for empty content.

  ## Props

    * `:icon` — string, icon name
    * `:title` — string, heading text
    * `:message` — string, description text
    * `:action_label` — string, CTA button label
    * `:on_action` — {pid, tag} tuple for the CTA
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.empty_state(icon: "inbox", title: "Nothing here yet", message: "Your items will appear here.", action_label: "Get started", on_action: :start)
  """
  @spec empty_state(keyword() | map()) :: map()
  def empty_state(props \\ [])
  def empty_state(props) when is_list(props), do: empty_state(Map.new(props))

  def empty_state(%{} = props) do
    %{
      type: :empty_state,
      props:
        Map.take(props, [
          :icon,
          :title,
          :message,
          :action_label,
          :on_action,
          :accessibility_id,
          :accessibility_label,
          :accessibility_hint,
          :accessibility_role,
          :accessibility_value,
          :accessibility_hidden
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:spacer` leaf node. Flexible or fixed space.

  ## Props

    * `:size` — fixed size in pt (omit for flexible spacer that fills available space)

  ## Examples

      Dala.Ui.Widgets.spacer()          # flexible — fills available space
      Dala.Ui.Widgets.spacer(size: 20)  # fixed 20pt gap
  """
  @spec spacer(keyword() | map()) :: map()
  def spacer(props \\ [])
  def spacer(props) when is_list(props), do: spacer(Map.new(props))

  def spacer(%{} = props) do
    # Native side reads "fixed_size" from props
    props = Map.put(props, :fixed_size, Map.get(props, :size))

    %{
      type: :spacer,
      props: Map.take(props, [:fixed_size, :size]),
      children: []
    }
  end

  @doc """
  Returns a `:text_field` leaf node. A single-line text input.

  ## Props

    * `:text` — initial/current text value
    * `:placeholder` — placeholder text when empty
    * `:on_change` — `{pid, tag}` tuple; fired on every text change with new value
    * `:on_focus` — `{pid, tag}` tuple; fired when field gains focus
    * `:on_blur` — `{pid, tag}` tuple; fired when field loses focus
    * `:on_submit` — `{pid, tag}` tuple; fired when return key is pressed
    * `:on_compose` — `{pid, tag}` tuple; IME composition events (CJK, etc.)
    * `:keyboard_type` — `:default`, `:number`, `:decimal`, `:email`, `:phone`, `:url`
    * `:return_key` — `:done`, `:next`, `:go`, `:search`, `:send`
    * `:text_color`, `:text_size` — typography
    * `:background`, `:padding`, `:corner_radius` — layout
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.text_field(placeholder: "Enter name", on_change: {self(), :name_changed})
      Dala.Ui.Widgets.text_field(keyboard_type: :email, return_key: :next, on_submit: {self(), :next_field})
  """
  @spec text_field(keyword() | map()) :: map()
  def text_field(props \\ [])
  def text_field(props) when is_list(props), do: text_field(Map.new(props))

  def text_field(%{} = props) do
    allowed =
      [:text, :placeholder, :on_change, :on_focus, :on_blur, :on_submit, :on_compose] ++
        [:keyboard_type, :return_key] ++
        [:text_color, :text_size] ++
        [:background, :padding, :corner_radius] ++
        @accessibility_props ++
        [:secure, :max_length, :auto_capitalize, :auto_correct, :min_lines, :max_lines]

    %{
      type: :text_field,
      props: Map.take(props, allowed),
      children: []
    }
  end

  @doc """
  Returns a `:toggle` leaf node. A boolean toggle switch.

  ## Props

    * `:value` — boolean, on/off state (default: false)
    * `:on_change` — `{pid, tag}` tuple; fired with new boolean value on toggle
    * `:text` — optional label text displayed beside the switch
    * `:track_color` — color when switch is on
    * `:thumb_color` — color of the draggable thumb
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.toggle(value: true, on_change: {self(), :notifications_toggled}, text: "Notifications")
  """
  @spec toggle(keyword() | map()) :: map()
  def toggle(props \\ [])
  def toggle(props) when is_list(props), do: toggle(Map.new(props))

  def toggle(%{} = props) do
    %{
      type: :toggle,
      props:
        Map.take(props, [
          :value,
          :on_change,
          :text,
          :disabled,
          :text_color,
          :text_size,
          :track_color,
          :thumb_color,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:slider` leaf node. A continuous range slider.

  ## Props

    * `:value` — current value (default: 0.5)
    * `:min_value` — minimum value (default: 0.0)
    * `:max_value` — maximum value (default: 1.0)
    * `:on_change` — `{pid, tag}` tuple; fired with new float value on drag
    * `:color` — slider tint color
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.slider(value: 0.5, min_value: 0, max_value: 100, on_change: {self(), :volume_changed})
  """
  @spec slider(keyword() | map()) :: map()
  def slider(props \\ [])
  def slider(props) when is_list(props), do: slider(Map.new(props))

  def slider(%{} = props) do
    %{
      type: :slider,
      props:
        Map.take(props, [:value, :min_value, :max_value, :on_change, :color, :accessibility_id]),
      children: []
    }
  end

  @doc """
  Returns a `:tab_bar` container node. A tab navigation bar.

  ## Props

    * `:tabs` — list of tab definitions, each a map with `:id`, `:label`, and optional `:icon`
    * `:active_tab` — the id of the currently selected tab
    * `:on_tab_select` — `{pid, tag}` tuple; fired with selected tab id string
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.tab_bar(
        tabs: [
          %{id: "home", label: "Home", icon: "home"},
          %{id: "settings", label: "Settings", icon: "settings"}
        ],
        active_tab: "home",
        on_tab_select: {self(), :tab_changed}
      )
  """
  @spec tab_bar(keyword() | map()) :: map()
  def tab_bar(props \\ [])
  def tab_bar(props) when is_list(props), do: tab_bar(Map.new(props))

  def tab_bar(%{} = props) do
    %{
      type: :tab_bar,
      props: Map.take(props, [:tabs, :active_tab, :on_tab_select, :accessibility_id]),
      children: []
    }
  end

  @doc """
  Returns a `:video` leaf node. An inline video player.

  ## Props

    * `:src` — video URL (required)
    * `:autoplay` — boolean, start playing immediately (default: false)
    * `:loop` — boolean, loop playback (default: false)
    * `:controls` — boolean, show playback controls (default: true)
    * `:width`, `:height` — dimensions in dp/pts; omit to fill parent

  ## Examples

      Dala.Ui.Widgets.video(src: "https://example.com/clip.mp4", autoplay: true, loop: true)
  """
  @spec video(keyword() | map()) :: map()
  def video(props \\ [])
  def video(props) when is_list(props), do: video(Map.new(props))

  def video(%{} = props) do
    src = props[:src] || props[:source] || ""
    props = Map.put(props, :src, src)

    %{
      type: :video,
      props:
        Map.take(props, [
          :src,
          :source,
          :autoplay,
          :loop,
          :muted,
          :controls,
          :width,
          :height,
          :accessibility_id
        ]),
      children: []
    }
  end

  # ── Existing components (expanded prop support) ───────────────────────────

  @doc """
  Returns an `:image` leaf node. Displays an image from a URL or local asset.

  ## Props

    * `:src` — URL or local asset name (required)
    * `:resize_mode` — `:cover` (default), `:contain`, `:stretch`, `:repeat`
    * `:width`, `:height` — dimensions in dp/pts; omit to auto-size
    * `:corner_radius` — optional rounded corners
    * `:placeholder_color` — color shown while loading
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.image(src: "https://example.com/photo.jpg", resize_mode: :cover, corner_radius: 12)
  """
  @spec image(keyword() | map()) :: map()
  def image(props \\ [])
  def image(props) when is_list(props), do: image(Map.new(props))

  def image(%{} = props) do
    src = props[:src] || props[:source] || ""
    props = Map.put(props, :src, src)

    %{
      type: :image,
      props:
        Map.take(props, [
          :src,
          :source,
          :resize_mode,
          :width,
          :height,
          :corner_radius,
          :background,
          :placeholder_color,
          :accessibility_id,
          :on_error,
          :on_load
        ]),
      children: []
    }
  end

  @doc """
  Returns an `:avatar` leaf node. Profile image with fallback initials.

  ## Props

    * `:src` — string, image URL (nil shows fallback)
    * `:fallback` — string, 1-2 character initials shown when src is nil/fails
    * `:size` — number, diameter in dp/pt (default: 40)
    * `:shape` — :circle or :rounded_square (default: :circle)
    * `:background` — background color for fallback state
    * `:text_color` — text color for fallback initials
    * `:on_tap` — {pid, tag} tuple
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.avatar(src: @user.photo_url, fallback: "JS", size: 48, shape: :circle)
      Dala.Ui.Widgets.avatar(fallback: "AB", background: :primary, text_color: :on_primary, size: 40)
  """
  @spec avatar(keyword() | map()) :: map()
  def avatar(props \\ [])
  def avatar(props) when is_list(props), do: avatar(Map.new(props))

  def avatar(%{} = props) do
    %{
      type: :avatar,
      props:
        Map.take(props, [
          :src,
          :fallback,
          :size,
          :shape,
          :background,
          :text_color,
          :on_tap,
          :accessibility_id,
          :accessibility_label,
          :accessibility_hint,
          :accessibility_role,
          :accessibility_value,
          :accessibility_hidden
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:switch` leaf node. A boolean toggle switch.

  Prefer `toggle/1` for new code — it uses `:on_change` consistent with other
  value widgets. This function is kept for backward compatibility.

  ## Props

    * `:value` — boolean, on/off state (default: false)
    * `:on_toggle` — `{pid, tag}` tuple; fires `{:toggle, tag, new_value}` to handler
    * `:track_color` — color when switch is on
    * `:thumb_color` — color of the draggable thumb
  """
  @spec switch(keyword() | map()) :: map()
  def switch(props \\ [])
  def switch(props) when is_list(props), do: switch(Map.new(props))

  def switch(%{} = props) do
    %{
      type: :switch,
      props:
        Map.take(props, [
          :value,
          :on_toggle,
          :disabled,
          :text,
          :text_color,
          :track_color,
          :thumb_color,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:stepper` leaf node. Multi-step indicator for forms and onboarding.

  ## Props

    * `:steps` — list of label strings (required)
    * `:current` — 0-based index of the current step
    * `:color` — active step color
    * `:connector_color` — color of the line connecting steps
    * `:completed_icon` — icon name for completed steps (default: "check")
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.stepper(steps: ["Account", "Profile", "Done"], current: @step)
  """
  @spec stepper(keyword() | map()) :: map()
  def stepper(props \\ [])
  def stepper(props) when is_list(props), do: stepper(Map.new(props))

  def stepper(%{} = props) do
    %{
      type: :stepper,
      props:
        Map.take(props, [
          :steps,
          :current,
          :color,
          :connector_color,
          :completed_icon,
          :accessibility_id,
          :accessibility_label,
          :accessibility_hint,
          :accessibility_role,
          :accessibility_value,
          :accessibility_hidden
        ]),
      children: []
    }
  end

  @doc """
  Returns an `:activity_indicator` leaf node. Displays a circular loading spinner.

  ## Props

    * `:size` — `:small` or `:large` (default: `:small`)
    * `:color` — spinner color (default: theme primary)
    * `:animating` — whether spinner is animating (default: true)
  """
  @spec activity_indicator(keyword() | map()) :: map()
  def activity_indicator(props \\ [])
  def activity_indicator(props) when is_list(props), do: activity_indicator(Map.new(props))

  def activity_indicator(%{} = props) do
    %{
      type: :activity_indicator,
      props: Map.take(props, [:size, :color, :animating, :accessibility_id]),
      children: []
    }
  end

  @doc """
  Returns a `:skeleton` leaf node. Animated shimmer placeholder for loading content.

  ## Props

    * `:width` — number or `:fill`, placeholder width
    * `:height` — number, placeholder height
    * `:corner_radius` — rounded corners
    * `:color` — base color for the shimmer
    * `:animate` — boolean, enable shimmer animation (default: true)
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.skeleton(width: 200, height: 16, corner_radius: :radius_sm)
      Dala.Ui.Widgets.skeleton(width: :fill, height: 120, corner_radius: :radius_md)
  """
  @spec skeleton(keyword() | map()) :: map()
  def skeleton(props \\ [])
  def skeleton(props) when is_list(props), do: skeleton(Map.new(props))

  def skeleton(%{} = props) do
    %{
      type: :skeleton,
      props:
        Map.take(props, [
          :width,
          :height,
          :corner_radius,
          :color,
          :animate,
          :accessibility_id,
          :accessibility_label,
          :accessibility_hint,
          :accessibility_role,
          :accessibility_value,
          :accessibility_hidden
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:modal` container node. Presents content above the enclosing view.

  ## Props

    * `:visible` — boolean, controls whether modal is shown (default: false)
    * `:on_dismiss` — `{pid, tag}` tuple; fired when user dismisses modal
    * `:presentation_style` — `:full_screen` (default) or `:page_sheet`

  ## Examples

      Dala.Ui.Widgets.modal([visible: true, on_dismiss: {self(), :dismissed}], [
        Dala.Ui.Widgets.text(text: "Modal content")
      ])
  """
  @spec modal(keyword() | map(), list()) :: map()
  def modal(props, children \\ [])
  def modal(props, children) when is_list(props), do: modal(Map.new(props), children)

  def modal(%{} = props, children) when is_list(children) do
    %{
      type: :modal,
      props:
        Map.take(props, [
          :visible,
          :on_dismiss,
          :presentation_style,
          :animation,
          :drag_indicator,
          :background,
          :corner_radius,
          :accessibility_id
        ]),
      children: children
    }
  end

  @doc """
  Returns a `:refresh_control` leaf node. Adds pull-to-refresh to ScrollView.

  Attach as a child of `:scroll` node. The scroll node handles the refresh gesture.

  ## Props

    * `:on_refresh` — `{pid, tag}` tuple; fired when user pulls to refresh
    * `:refreshing` — boolean, true while refresh is in progress
    * `:tint_color` — color of the refresh spinner
  """
  @spec refresh_control(keyword() | map()) :: map()
  def refresh_control(props \\ [])
  def refresh_control(props) when is_list(props), do: refresh_control(Map.new(props))

  def refresh_control(%{} = props) do
    %{
      type: :refresh_control,
      props: Map.take(props, [:on_refresh, :refreshing, :tint_color, :accessibility_id]),
      children: []
    }
  end

  @doc """
  Returns a `:scroll` container node. A scrollable view (ScrollView equivalent).

  ## Props

    * `:direction` — `:vertical` (default) or `:horizontal`
    * `:shows_indicator` — boolean, show scroll indicator (default: true)
    * `:on_end_reached` — `{pid, tag}` tuple; fired when scroll reaches bottom/end
    * `:on_scroll` — `{pid, tag}` tuple; fired during scrolling with scroll position
    * `:padding`, `:background` — layout props

  ## Examples

      Dala.Ui.Widgets.scroll([padding: :space_md], [
        Dala.Ui.Widgets.text(text: "Long content...")
      ])
  """
  @spec scroll(keyword() | map(), list()) :: map()
  def scroll(props, children \\ [])
  def scroll(props, children) when is_list(props), do: scroll(Map.new(props), children)

  def scroll(%{} = props, children) when is_list(children) do
    allowed =
      [:horizontal, :show_indicator, :on_end_reached, :on_scroll] ++
        [:padding, :background] ++
        [:paging]

    %{
      type: :scroll,
      props: Map.take(props, allowed),
      children: children
    }
  end

  @doc """
  Returns a `:grid` container node. Grid layout for photo grids, card grids, etc.

  ## Props

    * `:columns` — integer, number of columns (default: 2)
    * `:gap` — spacing between cells (accepts spacing tokens)
    * `:row_gap` — vertical gap between rows (falls back to :gap)
    * `:padding`, `:padding_top`, `:padding_right`, `:padding_bottom`, `:padding_left`
    * `:background` — background color
    * `:corner_radius` — rounded corners
    * `:fill_width` — boolean, stretch to fill parent width
    * `:on_tap`, `:on_long_press` — gesture handlers
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.grid(columns: 2, gap: :space_sm, padding: :space_md, [
        Dala.Ui.Widgets.text(text: "Cell 1"),
        Dala.Ui.Widgets.text(text: "Cell 2")
      ])
  """
  @spec grid(keyword() | map(), list()) :: map()
  def grid(props, children \\ [])
  def grid(props, children) when is_list(props), do: grid(Map.new(props), children)

  def grid(%{} = props, children) when is_list(children) do
    allowed =
      [
        :columns,
        :gap,
        :row_gap,
        :padding,
        :padding_top,
        :padding_right,
        :padding_bottom,
        :padding_left,
        :background,
        :corner_radius,
        :fill_width,
        :on_tap,
        :on_long_press,
        :accessibility_id,
        :accessibility_label,
        :accessibility_hint,
        :accessibility_role,
        :accessibility_value,
        :accessibility_hidden
      ]

    %{
      type: :grid,
      props: Map.take(props, allowed),
      children: children
    }
  end

  @doc """
  Returns a `:pressable` container node. A pressable wrapper.

  ## Props

    * `:on_press` — `{pid, tag}` tuple; fired when pressed
    * `:on_long_press` — `{pid, tag}` tuple; fired on long press

  ## Examples

      Dala.Ui.Widgets.pressable([on_press: {self(), :card_tapped}], [
        Dala.Ui.Widgets.text(text: "Tap me")
      ])
  """
  @spec pressable(keyword() | map(), list()) :: map()
  def pressable(props, children \\ [])
  def pressable(props, children) when is_list(props), do: pressable(Map.new(props), children)

  def pressable(%{} = props, children) when is_list(children) do
    %{
      type: :pressable,
      props:
        Map.take(props, [
          :on_press,
          :on_long_press,
          :on_double_tap,
          :disabled,
          :accessibility_id
        ]),
      children: children
    }
  end

  @doc """
  Returns a `:safe_area` container node. Applies safe area insets.

  Renders children within the safe area boundaries (avoiding notches, status bar, etc.).
  """
  @spec safe_area(keyword() | map() | list()) :: map()
  def safe_area(children_or_props \\ [])

  def safe_area(children) when is_list(children) do
    %{type: :safe_area, props: %{}, children: children}
  end

  def safe_area(%{} = props) do
    safe_area(props, [])
  end

  @spec safe_area(keyword() | map(), list()) :: map()
  def safe_area(props, children) when is_list(props) do
    safe_area(Map.new(props), children)
  end

  def safe_area(%{} = props, children) when is_list(children) do
    %{
      type: :safe_area,
      props: Map.take(props, [:edges, :background, :accessibility_id]),
      children: children
    }
  end

  @doc """
  Returns a `:status_bar` leaf node. Controls the status bar appearance.

  ## Props

    * `:bar_style` — `:default` (dark text) or `:light_content` (light text)
    * `:hidden` — boolean, hides the status bar (default: false)
  """
  @spec status_bar(keyword() | map()) :: map()
  def status_bar(props \\ [])
  def status_bar(props) when is_list(props), do: status_bar(Map.new(props))

  def status_bar(%{} = props) do
    %{
      type: :status_bar,
      props: Map.take(props, [:bar_style, :hidden, :background, :accessibility_id]),
      children: []
    }
  end

  @doc """
  Returns a `:progress_bar` leaf node. Displays a progress bar.

  ## Props

    * `:progress` — float 0.0 to 1.0, current progress (default: 0.0)
    * `:indeterminate` — boolean, shows indeterminate spinner (default: false)
    * `:color` — progress bar color
  """
  @spec progress_bar(keyword() | map()) :: map()
  def progress_bar(props \\ [])
  def progress_bar(props) when is_list(props), do: progress_bar(Map.new(props))

  def progress_bar(%{} = props) do
    %{
      type: :progress_bar,
      props:
        Map.take(props, [
          :progress,
          :indeterminate,
          :color,
          :background,
          :height,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:list` node. A data-driven list (FlatList equivalent).

  Leverages `Dala.Ui.List` for rendering. Requires an `:id` prop to identify the list
  for selection events and custom renderers.

  ## Props

    * `:data` — enumerable of items to render (mapped to `:items`)
    * `:id` — atom identifier for the list (required for selection events)
    * `:on_end_reached` — `{pid, tag}` tuple; fired when list reaches end
    * `:scroll` — boolean, enables scrolling (default: true)

  For custom item rendering, register a renderer via `Dala.Ui.List.put_renderer/3` in `mount/3`.

  ## Examples

      Dala.Ui.Widgets.list(id: :my_list, data: assigns.items)

      # With custom renderer in mount/3:
      # Dala.Ui.List.put_renderer(socket, :my_list, fn item -> ... end)
  """
  @spec list(keyword() | map()) :: map()
  def list(props \\ [])
  def list(props) when is_list(props), do: list(Map.new(props))

  def list(%{} = props) do
    items = props[:data] || props[:items] || []
    list_props = props |> Map.drop([:data]) |> Map.put(:items, items)

    %{
      type: :list,
      props:
        Map.take(list_props, [
          :id,
          :items,
          :data,
          :on_end_reached,
          :on_refresh,
          :refreshing,
          :empty_text,
          :separator,
          :scroll,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:webview` component node. Renders a native web view inline.

  The JS bridge is injected automatically — the page can call `window.dala.send(data)`
  to deliver messages to `handle_info({:webview, :message, data}, socket)`, and
  Elixir can push to JS via `Dala.WebView.post_message/2`.

  ## Props

    * `:url` — URL to load (required)
    * `:allow` — list of URL prefixes that navigation is permitted to (default: allow all).
      Blocked attempts arrive as `{:webview, :blocked, url}` in `handle_info`.
    * `:show_url` — show a native URL label above the WebView (default: false)
    * `:title` — static title label above the WebView; overrides `:show_url`
    * `:width`, `:height` — dimensions in dp/pts; omit to fill parent
  """
  @spec webview(keyword() | map()) :: map()
  def webview(props \\ [])
  def webview(props) when is_list(props), do: webview(Map.new(props))

  def webview(%{} = props) do
    allow_str = (props[:allow] || []) |> Enum.join(",")
    url = props[:url] || props[:source] || ""

    node_props =
      %{url: url, allow: allow_str, show_url: props[:show_url] || false}
      |> then(fn p -> if props[:title], do: Map.put(p, :title, props[:title]), else: p end)
      |> then(fn p -> if props[:width], do: Map.put(p, :width, props[:width]), else: p end)
      |> then(fn p -> if props[:height], do: Map.put(p, :height, props[:height]), else: p end)
      |> then(fn p ->
        if props[:accessibility_id],
          do: Map.put(p, :accessibility_id, props[:accessibility_id]),
          else: p
      end)

    %{type: :web_view, props: node_props, children: []}
  end

  @doc """
  Returns a `:camera_preview` component node. Renders a live camera feed inline.

  Call `Dala.Media.Camera.start_preview/2` before mounting this component, and
  `Dala.Media.Camera.stop_preview/1` when done.

  ## Props

    * `:facing` — `:back` (default) or `:front`
    * `:width`, `:height` — dimensions in dp/pts; omit to fill parent
  """
  @spec camera_preview(keyword() | map()) :: map()
  def camera_preview(props \\ [])
  def camera_preview(props) when is_list(props), do: camera_preview(Map.new(props))

  def camera_preview(%{} = props) do
    %{
      type: :camera_preview,
      props: Map.take(props, [:facing, :width, :height]),
      children: []
    }
  end

  @doc """
  Returns a `:checkbox` leaf node. A checkbox with an optional label.

  ## Props

    * `:value` — boolean, checked state (default: false)
    * `:on_change` — `{pid, tag}` tuple; fired with new boolean value on change
    * `:label` — string, label text displayed beside the checkbox
    * `:color` — color token for the checkbox tint
    * `:enabled` — boolean, whether the checkbox is interactive (default: true)
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.checkbox(value: true, on_change: {self(), :agree_toggled}, label: "I agree")
  """
  @spec checkbox(keyword() | map()) :: map()
  def checkbox(props \\ [])
  def checkbox(props) when is_list(props), do: checkbox(Map.new(props))

  def checkbox(%{} = props) do
    %{
      type: :checkbox,
      props: Map.take(props, [:value, :on_change, :label, :color, :enabled, :accessibility_id]),
      children: []
    }
  end

  @doc """
  Returns a `:radio` leaf node. A radio button within a group.

  ## Props

    * `:selected` — boolean, whether this radio is selected
    * `:on_select` — `{pid, tag}` tuple; fired when this radio is selected
    * `:label` — string, label text displayed beside the radio
    * `:group` — string, radio group name (radios in the same group are mutually exclusive)
    * `:enabled` — boolean, whether the radio is interactive
    * `:color` — color token for the radio tint
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.radio(selected: true, on_select: {self(), :option_a}, label: "Option A", group: "choices")
  """
  @spec radio(keyword() | map()) :: map()
  def radio(props \\ [])
  def radio(props) when is_list(props), do: radio(Map.new(props))

  def radio(%{} = props) do
    %{
      type: :radio,
      props:
        Map.take(props, [
          :selected,
          :on_select,
          :label,
          :group,
          :enabled,
          :color,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:card` container node. A Material-style card with elevation and variants.

  ## Props

    * `:elevation` — float, shadow depth
    * `:variant` — `:filled`, `:outlined`, or `:elevated`
    * `:background` — background color
    * `:padding`, `:padding_top`, `:padding_right`, `:padding_bottom`, `:padding_left`
    * `:border_color`, `:border_width` — border styling
    * `:corner_radius` — rounded corners
    * `:on_tap` — `{pid, tag}` tuple; fired when card is tapped
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.card([variant: :elevated, elevation: 2.0, corner_radius: 12], [
        Dala.Ui.Widgets.text(text: "Card content")
      ])
  """
  @spec card(keyword() | map(), list()) :: map()
  def card(props, children \\ [])
  def card(props, children) when is_list(props), do: card(Map.new(props), children)

  def card(%{} = props, children) when is_list(children) do
    %{
      type: :card,
      props:
        Map.take(props, [
          :elevation,
          :variant,
          :background,
          :padding,
          :padding_top,
          :padding_right,
          :padding_bottom,
          :padding_left,
          :border_color,
          :border_width,
          :corner_radius,
          :on_tap,
          :accessibility_id
        ]),
      children: children
    }
  end

  @doc """
  Returns a `:badge` container node. Displays a numeric badge over its children.

  ## Props

    * `:count` — integer, numeric badge value
    * `:color` — badge background color
    * `:text_color` — badge text color
    * `:visible` — boolean, whether the badge is shown (default: true)

  ## Examples

      Dala.Ui.Widgets.badge([count: 5, color: :error], [
        Dala.Ui.Widgets.icon(name: "notifications")
      ])
  """
  @spec badge(keyword() | map(), list()) :: map()
  def badge(props, children \\ [])
  def badge(props, children) when is_list(props), do: badge(Map.new(props), children)

  def badge(%{} = props, children) when is_list(children) do
    %{
      type: :badge,
      props:
        Map.take(props, [
          :count,
          :color,
          :text_color,
          :text_size,
          :position,
          :visible,
          :accessibility_id
        ]),
      children: children
    }
  end

  @doc """
  Returns a `:chip` leaf node. A compact Material Design chip.

  ## Props

    * `:label` — string, chip text (required)
    * `:variant` — `:assist`, `:filter`, `:input`, or `:suggestion`
    * `:selected` — boolean, selected state (for filter chips)
    * `:on_tap` — `{pid, tag}` tuple; fired when chip is tapped
    * `:icon` — string, icon name displayed before the label
    * `:on_remove` — `{pid, tag}` tuple; fired when remove icon is tapped (input chips)
    * `:enabled` — boolean, whether the chip is interactive
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.chip(label: "Filter", variant: :filter, selected: true, on_tap: {self(), :chip_tapped})
  """
  @spec chip(keyword() | map()) :: map()
  def chip(props \\ [])
  def chip(props) when is_list(props), do: chip(Map.new(props))

  def chip(%{} = props) do
    %{
      type: :chip,
      props:
        Map.take(props, [
          :label,
          :variant,
          :selected,
          :on_tap,
          :icon,
          :on_remove,
          :disabled,
          :enabled,
          :text_color,
          :text_size,
          :background,
          :corner_radius,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:snackbar` leaf node. A transient message bar with an optional action.

  ## Props

    * `:message` — string, the message text (required)
    * `:action_label` — string, label for the optional action button
    * `:on_action` — `{pid, tag}` tuple; fired when the action button is tapped
    * `:duration` — `:short` or `:long`
    * `:visible` — boolean, whether the snackbar is shown

  ## Examples

      Dala.Ui.Widgets.snackbar(message: "Item deleted", action_label: "Undo", on_action: {self(), :undo})
  """
  @spec snackbar(keyword() | map()) :: map()
  def snackbar(props \\ [])
  def snackbar(props) when is_list(props), do: snackbar(Map.new(props))

  def snackbar(%{} = props) do
    %{
      type: :snackbar,
      props:
        Map.take(props, [
          :message,
          :action_label,
          :on_action,
          :duration,
          :visible,
          :text_color,
          :background,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:bottom_sheet` container node. A slide-up panel anchored to the bottom.

  ## Props

    * `:visible` — boolean, whether the sheet is shown
    * `:on_dismiss` — `{pid, tag}` tuple; fired when the sheet is dismissed
    * `:drag_indicator` — boolean, show drag handle at top (default: true)
    * `:peek_height` — float, height of the sheet when partially visible
    * `:background` — background color
    * `:corner_radius` — rounded corners at the top

  ## Examples

      Dala.Ui.Widgets.bottom_sheet([visible: true, on_dismiss: {self(), :dismissed}, drag_indicator: true], [
        Dala.Ui.Widgets.text(text: "Sheet content")
      ])
  """
  @spec bottom_sheet(keyword() | map(), list()) :: map()
  def bottom_sheet(props, children \\ [])

  def bottom_sheet(props, children) when is_list(props),
    do: bottom_sheet(Map.new(props), children)

  def bottom_sheet(%{} = props, children) when is_list(children) do
    %{
      type: :bottom_sheet,
      props:
        Map.take(props, [
          :visible,
          :on_dismiss,
          :drag_indicator,
          :peek_height,
          :height,
          :background,
          :corner_radius,
          :accessibility_id
        ]),
      children: children
    }
  end

  @doc """
  Returns a `:tooltip` container node. Shows a tooltip over its children.

  ## Props

    * `:text` — string, tooltip text (required)
    * `:position` — `:top`, `:bottom`, `:left`, or `:right`

  ## Examples

      Dala.Ui.Widgets.tooltip([text: "Save changes", position: :top], [
        Dala.Ui.Widgets.icon(name: "save")
      ])
  """
  @spec tooltip(keyword() | map(), list()) :: map()
  def tooltip(props, children \\ [])
  def tooltip(props, children) when is_list(props), do: tooltip(Map.new(props), children)

  def tooltip(%{} = props, children) when is_list(children) do
    %{
      type: :tooltip,
      props:
        Map.take(props, [
          :text,
          :position,
          :visible,
          :delay,
          :accessibility_id
        ]),
      children: children
    }
  end

  @doc """
  Returns a `:fab` leaf node. A Floating Action Button.

  ## Props

    * `:icon` — string, icon name (required)
    * `:on_tap` — `{pid, tag}` tuple; fired when FAB is tapped
    * `:text` — string, optional label for extended FAB
    * `:background` — background color
    * `:color` — icon color
    * `:corner_radius` — rounded corners
    * `:elevation` — float, shadow depth
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.fab(icon: "add", on_tap: {self(), :add_item})
      Dala.Ui.Widgets.fab(icon: "edit", text: "Compose", on_tap: {self(), :compose})
  """
  @spec fab(keyword() | map()) :: map()
  def fab(props \\ [])
  def fab(props) when is_list(props), do: fab(Map.new(props))

  def fab(%{} = props) do
    %{
      type: :fab,
      props:
        Map.take(props, [
          :icon,
          :on_tap,
          :text,
          :background,
          :color,
          :text_color,
          :corner_radius,
          :elevation,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:icon_button` leaf node. A clickable icon button.

  ## Props

    * `:icon` — string, icon name (required)
    * `:on_tap` — `{pid, tag}` tuple; fired when button is tapped
    * `:selected` — boolean, toggle state for toggle icon buttons
    * `:enabled` — boolean, whether the button is interactive
    * `:color` — icon color
    * `:background` — background color
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.icon_button(icon: "favorite", on_tap: {self(), :favorite_tapped})
  """
  @spec icon_button(keyword() | map()) :: map()
  def icon_button(props \\ [])
  def icon_button(props) when is_list(props), do: icon_button(Map.new(props))

  def icon_button(%{} = props) do
    %{
      type: :icon_button,
      props:
        Map.take(props, [
          :icon,
          :on_tap,
          :selected,
          :enabled,
          :color,
          :text_color,
          :background,
          :size,
          :disabled,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:segmented_button` leaf node. A segmented control with multiple segments.

  ## Props

    * `:segments` — list of maps, each with `:id`, `:label`, and optional `:icon`
    * `:selected` — the id of the currently selected segment
    * `:on_select` — `{pid, tag}` tuple; fired with selected segment id
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.segmented_button(
        segments: [%{id: "day", label: "Day"}, %{id: "week", label: "Week"}, %{id: "month", label: "Month"}],
        selected: "week",
        on_select: {self(), :range_changed}
      )
  """
  @spec segmented_button(keyword() | map()) :: map()
  def segmented_button(props \\ [])
  def segmented_button(props) when is_list(props), do: segmented_button(Map.new(props))

  def segmented_button(%{} = props) do
    %{
      type: :segmented_button,
      props:
        Map.take(props, [
          :segments,
          :selected,
          :on_select,
          :text_color,
          :background,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:app_bar` leaf node. A top app bar with title and action icons.

  ## Props

    * `:title` — string, app bar title
    * `:leading_icon` — string, icon name for the leading navigation icon
    * `:on_leading` — `{pid, tag}` tuple; fired when leading icon is tapped
    * `:trailing_actions` — list of maps with `:icon` and `:on_tap`
    * `:background` — background color
    * `:text_color` — title and icon color
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.app_bar(
        title: "My App",
        leading_icon: "back",
        on_leading: {self(), :back_pressed},
        trailing_actions: [%{icon: "search", on_tap: {self(), :search}}]
      )
  """
  @spec app_bar(keyword() | map()) :: map()
  def app_bar(props \\ [])
  def app_bar(props) when is_list(props), do: app_bar(Map.new(props))

  def app_bar(%{} = props) do
    %{
      type: :app_bar,
      props:
        Map.take(props, [
          :title,
          :leading_icon,
          :on_leading,
          :trailing_actions,
          :background,
          :text_color,
          :elevation,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:nav_bar` leaf node. A bottom navigation bar.

  ## Props

    * `:items` — list of maps, each with `:id`, `:label`, and `:icon`
    * `:active` — id of the currently active item
    * `:on_select` — `{pid, tag}` tuple; fired with selected item id
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.nav_bar(
        items: [%{id: "home", label: "Home", icon: "home"}, %{id: "profile", label: "Profile", icon: "user"}],
        active: "home",
        on_select: {self(), :tab_changed}
      )
  """
  @spec nav_bar(keyword() | map()) :: map()
  def nav_bar(props \\ [])
  def nav_bar(props) when is_list(props), do: nav_bar(Map.new(props))

  def nav_bar(%{} = props) do
    %{
      type: :nav_bar,
      props:
        Map.take(props, [
          :items,
          :active,
          :on_select,
          :text_color,
          :background,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:nav_drawer` leaf node. A side navigation drawer.

  ## Props

    * `:visible` — boolean, whether the drawer is shown
    * `:on_dismiss` — `{pid, tag}` tuple; fired when the drawer is dismissed
    * `:items` — list of maps, each with `:id`, `:label`, and `:icon`
    * `:active` — id of the currently active item
    * `:on_select` — `{pid, tag}` tuple; fired with selected item id
    * `:header` — string, optional header text at the top

  ## Examples

      Dala.Ui.Widgets.nav_drawer(
        visible: true,
        on_dismiss: {self(), :drawer_dismissed},
        items: [%{id: "home", label: "Home", icon: "home"}],
        active: "home",
        on_select: {self(), :nav_changed}
      )
  """
  @spec nav_drawer(keyword() | map()) :: map()
  def nav_drawer(props \\ [])
  def nav_drawer(props) when is_list(props), do: nav_drawer(Map.new(props))

  def nav_drawer(%{} = props) do
    %{
      type: :nav_drawer,
      props:
        Map.take(props, [
          :visible,
          :on_dismiss,
          :items,
          :active,
          :on_select,
          :header,
          :background,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:nav_rail` leaf node. A side navigation rail (for tablets/desktop).

  ## Props

    * `:items` — list of maps, each with `:id`, `:label`, and `:icon`
    * `:active` — id of the currently active item
    * `:on_select` — `{pid, tag}` tuple; fired with selected item id
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.nav_rail(
        items: [%{id: "home", label: "Home", icon: "home"}, %{id: "settings", label: "Settings", icon: "settings"}],
        active: "home",
        on_select: {self(), :rail_changed}
      )
  """
  @spec nav_rail(keyword() | map()) :: map()
  def nav_rail(props \\ [])
  def nav_rail(props) when is_list(props), do: nav_rail(Map.new(props))

  def nav_rail(%{} = props) do
    %{
      type: :nav_rail,
      props:
        Map.take(props, [
          :items,
          :active,
          :on_select,
          :text_color,
          :background,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:menu` leaf node. A popup menu with selectable items.

  ## Props

    * `:items` — list of maps, each with `:label`, `:action` (atom), and optional `:icon`
    * `:visible` — boolean, whether the menu is shown
    * `:on_dismiss` — `{pid, tag}` tuple; fired when the menu is dismissed
    * `:on_select` — `{pid, tag}` tuple; fired with selected item's action atom
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.menu(
        items: [%{label: "Edit", action: :edit}, %{label: "Delete", action: :delete}],
        visible: true,
        on_select: {self(), :menu_selected}
      )
  """
  @spec menu(keyword() | map()) :: map()
  def menu(props \\ [])
  def menu(props) when is_list(props), do: menu(Map.new(props))

  def menu(%{} = props) do
    %{
      type: :menu,
      props:
        Map.take(props, [
          :items,
          :visible,
          :on_dismiss,
          :on_select,
          :text_color,
          :background,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:date_picker` leaf node. A date selection dialog.

  ## Props

    * `:visible` — boolean, whether the picker is shown
    * `:on_select` — `{pid, tag}` tuple; fired with selected date string (ISO 8601)
    * `:on_dismiss` — `{pid, tag}` tuple; fired when the picker is dismissed
    * `:selected_date` — string, initial date in ISO 8601 format
    * `:min_date` — string, earliest selectable date
    * `:max_date` — string, latest selectable date
    * `:title` — string, optional title text

  ## Examples

      Dala.Ui.Widgets.date_picker(
        visible: true,
        on_select: {self(), :date_picked},
        selected_date: "2025-01-15"
      )
  """
  @spec date_picker(keyword() | map()) :: map()
  def date_picker(props \\ [])
  def date_picker(props) when is_list(props), do: date_picker(Map.new(props))

  def date_picker(%{} = props) do
    %{
      type: :date_picker,
      props:
        Map.take(props, [
          :visible,
          :on_select,
          :on_dismiss,
          :selected_date,
          :min_date,
          :max_date,
          :title,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:time_picker` leaf node. A time selection dialog.

  ## Props

    * `:visible` — boolean, whether the picker is shown
    * `:on_select` — `{pid, tag}` tuple; fired with selected time string (HH:MM)
    * `:on_dismiss` — `{pid, tag}` tuple; fired when the picker is dismissed
    * `:selected_time` — string, initial time in HH:MM format
    * `:title` — string, optional title text

  ## Examples

      Dala.Ui.Widgets.time_picker(
        visible: true,
        on_select: {self(), :time_picked},
        selected_time: "09:30"
      )
  """
  @spec time_picker(keyword() | map()) :: map()
  def time_picker(props \\ [])
  def time_picker(props) when is_list(props), do: time_picker(Map.new(props))

  def time_picker(%{} = props) do
    %{
      type: :time_picker,
      props:
        Map.take(props, [
          :visible,
          :on_select,
          :on_dismiss,
          :selected_time,
          :title,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:search_bar` leaf node. A search input bar with placeholder and callbacks.

  ## Props

    * `:placeholder` — string, placeholder text when empty
    * `:text` — string, current search text
    * `:on_change` — `{pid, tag}` tuple; fired on every text change
    * `:on_submit` — `{pid, tag}` tuple; fired when search is submitted
    * `:on_focus` — `{pid, tag}` tuple; fired when the bar gains focus
    * `:active` — boolean, whether the search bar is in active/expanded state
    * `:on_tap` — `{pid, tag}` tuple; fired when the search bar is tapped
    * `:accessibility_id` — test identifier

  ## Examples

      Dala.Ui.Widgets.search_bar(placeholder: "Search...", on_change: {self(), :search_changed}, on_submit: {self(), :search_submitted})
  """
  @spec search_bar(keyword() | map()) :: map()
  def search_bar(props \\ [])
  def search_bar(props) when is_list(props), do: search_bar(Map.new(props))

  def search_bar(%{} = props) do
    %{
      type: :search_bar,
      props:
        Map.take(props, [
          :placeholder,
          :text,
          :on_change,
          :on_submit,
          :on_focus,
          :active,
          :on_tap,
          :value,
          :text_color,
          :background,
          :corner_radius,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:carousel` leaf node. A horizontally scrolling carousel of items.

  ## Props

    * `:data` — enumerable of items to render
    * `:id` — atom identifier for the carousel
    * `:on_page_change` — `{pid, tag}` tuple; fired with new page index on swipe
    * `:loop` — boolean, enables infinite looping (default: false)
    * `:peek` — float, peek width for adjacent items

  ## Examples

      Dala.Ui.Widgets.carousel(id: :photo_carousel, data: assigns.photos, on_page_change: {self(), :page_changed})
  """
  @spec carousel(keyword() | map()) :: map()
  def carousel(props \\ [])
  def carousel(props) when is_list(props), do: carousel(Map.new(props))

  def carousel(%{} = props) do
    %{
      type: :carousel,
      props:
        Map.take(props, [
          :data,
          :id,
          :items,
          :on_page_change,
          :loop,
          :autoplay,
          :autoplay_interval,
          :peek,
          :accessibility_id
        ]),
      children: []
    }
  end

  @doc """
  Returns a `:native_view` node that renders a platform-native component.

  `module` must implement the `Dala.Ui.NativeView` behaviour and be registered
  on the native side via `dalaNativeViewRegistry`. The `:id` must be unique
  per screen — a duplicate raises at render time.

  All other props are passed to `mount/2` and `update/2` on the component.

  ## Example

      Dala.Ui.Widgets.native_view(MyApp.ChartComponent, id: :revenue_chart, data: @points)

  """
  @spec native_view(module(), keyword() | map()) :: map()
  def native_view(module, props \\ [])
  def native_view(module, props) when is_list(props), do: native_view(module, Map.new(props))

  def native_view(module, %{} = props) when is_atom(module) do
    %{type: :native_view, props: Map.put(props, :module, module), children: []}
  end
end
