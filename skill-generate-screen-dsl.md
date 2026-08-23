# Skill: Generate Dala Screen Modules with DSL Style

## Purpose

This skill teaches an AI agent how to generate Dala screen modules using the
Spark DSL declarative syntax. After reading this document, the agent can
autonomously create complete, correct screen modules without trial-and-error.

Every prop table below is verified against the component registry
(`Dala.Ui.Component`) — the same source the compiler validates against.
Unknown props fail the build, so never invent prop names.

---

## 0. Generation Workflow

Follow these steps in order for every new screen. Each step ends with a
verification you can run.

**Step 1 — Name the module and infer the screen name.**
`MyApp.TasksScreen` → screen name `:tasks` automatically (suffixes
`Screen`/`View`/`Page` are stripped, then snake_cased). Only pass `name:`
explicitly when the module name isn't suffix-friendly.

**Step 2 — List the state before writing any UI.**
One `attribute :key, :type, default: ...` line per value the UI reads.
Collections are `:list`, text inputs mirror a `:string`, flags are
`:boolean`. If a `@ref` appears in your planned UI with no attribute behind
it, declare it now — undeclared refs warn at compile time and render empty.

**Step 3 — Sketch the container skeleton.**
Standard nesting: `safe_area do scroll do column … end end`. Pick rows/
columns by direction; reach for `box` only for overlaps or fixed sizes.

**Step 4 — Fill in leaves, wiring every event atom as you go.**
Keep a running list of handler atoms (`on_tap: :save` → `:save`). Use
`{atom, arg}` tuples when a row-specific argument is needed
(`on_tap: {:remove, item.id}`).

**Step 5 — Write one `handle_event/3` clause per atom.**
Value components deliver `%{"value" => v}` in params. Navigation returns
via `Dala.Socket.push_screen/3` / `Dala.Screen.pop_screen/1`.

**Step 6 — Compile and read diagnostics literally.**

```bash
mix compile
```

Unknown prop → rename to the suggested registry prop (the build fails on
purpose). Missing-handler warning → add the clause. Undeclared `@ref`
warning → declare the attribute. Line numbers point at the offending code.

**Step 7 — Verify behaviour from the BEAM before screenshots.**

```bash
mix dala.push
mix dala.connect --no-iex   # prints node names + tunnels
```

```elixir
node = :"my_app_ios@127.0.0.1"
Dala.Test.screen(node)    # expected module?
Dala.Test.assigns(node)   # expected state after driving taps?
```

Screenshots (`mcp__ios-simulator__screenshot`) only when layout matters.

**Step 8 — Extract repetition into `defui` once it repeats.**
Define above first use; positional args only; bodies support the full DSL.

---

## 1. Module Skeleton

Every DSL screen module follows this exact structure:

```elixir
defmodule MyApp.SomeScreen do
  use Dala.Spark.Dsl

  attributes do
    attribute :key, :type, default: value
  end

  screen name: :screen_atom do
    # UI components here
  end

  # Event handlers below
  def handle_event(:event_atom, _params, socket) do
    {:noreply, socket}
  end
end
```

### Key rules

| Rule | Detail |
|------|--------|
| `use Dala.Spark.Dsl` | Always. (`use Dala.Screen` also works — it delegates to this DSL and adds the behaviour.) |
| `attributes do ... end` | Optional. Omit for stateless screens. |
| `screen name: :atom do` | Required unless inferable from the module name. |
| `handle_event/3` | One clause per event atom referenced in `on_tap` / `on_change` / etc. |
| Never write `mount/3` or `render/1` | The DSL generates both; manual definitions clash. |

The old `dala do ... end` wrapper still compiles but is **deprecated** —
write sections flat at module top level.

### Screen name inference

Omitting `name` infers it from the module name:

```elixir
defmodule MyApp.CounterScreen do
  use Dala.Spark.Dsl
  # Inferred name: :counter
  screen do
    text "Hello"
  end
end
```

Suffixes removed: `Screen`, `View`, `Page`. A module with `attributes`
but no `screen` also compiles (useful mid-refactor).

---

## 2. Attributes Section

Declares screen state. The DSL auto-generates `mount/3` from these.

```elixir
attributes do
  attribute :count, :integer, default: 0
  attribute :query, :string, default: ""
  attribute :enabled, :boolean, default: true
  attribute :ratio, :float, default: 0.5
  attribute :mode, :atom, default: :idle
  attribute :items, :list, default: []
  attribute :meta, :map, default: %{}
  attribute :token, :string            # no default → nil
end
```

### Rules

- Types: `:integer`, `:string`, `:boolean`, `:float`, `:atom`, `:list`,
  `:map`. Anything else fails compilation.
- Every attribute becomes an assign, initialised in generated `mount/3`.
- Do **not** write a manual `mount/3` — the transformer generates it.
- Assigns created later (e.g. in `handle_info`) work fine; they just don't
  get automatic defaults.

---

## 3. Screen Section

```elixir
screen name: :my_screen do
  # ...
end
```

`:name` identifies the screen in navigation and debugging. See inference
above for omitting it.

### @ref syntax — reading state into the UI

Three positions:

```elixir
text "Count: @count"          # interpolated into any string prop
button "@confirm_label"       # whole-string ref
slider value: @volume         # bare ref in any prop position
```

- Refs resolve against declared **attributes** plus the framework-provided
  `@safe_area` map (`@safe_area.top`, `.bottom`, …).
- A ref matching no attribute emits a **compile warning** ("renders empty")
  with the declared list — fix the typo or add the attribute.
- Bare *variables* are rejected with a hint (`text mystery` → use
  `@mystery`). Loop variables are exempt inside their `for` block.

### Computed props (`compute/1`)

Any 1-arity fn prop runs with live assigns at render time:

```elixir
text text: compute(fn assigns ->
      case assigns[:score] do
        nil -> "—"
        s -> "#{s} pts"
      end
    end)
```

Use for formatting, derived colours, and conditions that need more than a
bare ref.

### Local components (`defui`)

Reusable fragments defined in the same module, **above first use**:

```elixir
defui stat_card(label, value) do
  card padding: 16 do
    column gap: 4 do
      text label, variant: :caption
      text value, variant: :title
    end
  end
end

screen name: :dashboard do
  column gap: 12 do
    stat_card("Revenue", "$12.4k")
    stat_card("Users", "1,203")
  end
end
```

Rules:

- Positional args only — wrong arity or `do`-blocks fail compilation.
- Bodies support the full DSL; `@ref`s resolve against caller assigns.
- Single-level field access on params works (`text user.name`).
- Usable inside `for` blocks; a parameter cannot cross the loop boundary
  (compile error) — read values from the item instead.
- Event atoms referenced inside `defui` bodies aren't seen by compile-time
  handler verification.

---

## 3.5 PubSub Section

Topics subscribe on mount and unsubscribe on terminate:

```elixir
pubsub do
  subscribe "chat:room:123", on_message: :handle_chat
end

def handle_chat({:message, text}, socket) do
  messages = socket.assigns.messages ++ [text]
  {:noreply, Dala.Socket.assign(socket, :messages, messages)}
end
```

Broadcasting (with `Dala.PubSub` started in your tree as
`{Dala.PubSub, name: MyApp.PubSub}`):

```elixir
Dala.PubSub.broadcast(MyApp.PubSub, "chat:room:123", {:message, "Hello!"})
```

---

## 3.6 Control Flow

`if` / `unless` / `for` work inside screen blocks and expand at render time:

```elixir
if @loading do
  activity_indicator size: :large
else
  text "Ready"
end

unless @archived do
  button "Delete", on_tap: :delete
end

for task <- @tasks, id: task.id do
  text task.title
end
```

Condition rules:

| Allowed | Example |
|---------|---------|
| Attribute ref | `@loading` |
| Plain literal | `true`, `"x"` |
| compute function | `compute(fn assigns -> map_size(assigns[:errors] || %{}) > 0 end)` |

Anything else (e.g. `Map.get(@x, :k) == nil`) is rejected at compile time —
wrap it in `compute/1`.

Loop rules:

- The `<-` source must be an `@ref`, literal list, or `compute/1`.
- Inside the block: bare item (`text item`) and single-level field access
  (`item.label`, atom-keyed maps/structs) both work.
- **Key rows** with `id: item.field` — keyed rows get stable ids
  (`<parent>:item-<key>`) so the diff engine patches individual rows.
- Outer variables don't cross nested-loop boundaries (compile error).

---

## 4. Component Catalogue

Syntax rules (enforced by the compiler):

- **Containers**: keyword-arg props on the call, children inside `do…end`.
  Prop-call style inside the block (`column do gap 8 end`) is a compile
  error with a hint.
- **Leaves**: optional positional content + keyword props. No children.
- All components accept `accessibility_id` plus `accessibility_label`,
  `accessibility_hint`, `accessibility_role`, `accessibility_value`,
  `accessibility_hidden`.

### 4.1 Containers

#### `column` / `row` — vertical / horizontal stack

```elixir
column padding: 16, gap: 12, alignment: :center do
  text "Title"
  row gap: 8 do
    icon "settings"
    text "Settings"
  end
end
```

Props: `padding`, `padding_top/right/bottom/left`, `gap`, `spacing`,
`background`, `corner_radius`, `fill_width`, `fill_height`, `alignment`,
`cross_alignment`, `scrollable`, `on_tap`, `on_long_press`.

#### `box` — overlap / sized box (ZStack)

Props: column's set plus `width`, `height`, `min_width`, `min_height`,
`max_width`, `max_height`. Children overlap (last on top).

#### `scroll` — scrollable region

```elixir
scroll direction: :vertical, shows_indicator: true, padding: 16 do
  text "Long content..."
end
```

Props: `direction` (`:vertical`/`:horizontal`), `shows_indicator`,
`on_scroll`, `padding`, `background`, `fill_width`, `fill_height`.
(No `gap`; use an inner column.)

#### `safe_area` — notch/home-indicator insets

Props: `edges`, `background`.

#### `modal` — modal overlay

Props: `visible`, `on_dismiss`, `presentation_style`
(`:full_screen`/`:page_sheet`), `animation`, `drag_indicator`,
`background`, `corner_radius`.

#### `pressable` — tappable wrapper

Props: `on_press`, `on_long_press`, `on_double_tap`, `disabled`.

#### `card` — elevated surface

Props: `variant`, `elevation`, `corner_radius`, `padding`, `background`,
`fill_width`, `on_tap`, `on_long_press`.

#### `grid` — grid layout

Props: `columns`, `gap`, `row_gap`, plus column's layout set.

#### `badge` — notification dot wrapper

Props: `count`, `color`, `text_color`, `text_size`, `position`, `visible`.

#### `bottom_sheet` — draggable sheet

Props: `visible`, `on_dismiss`, `drag_indicator`, `height`,
`corner_radius`, `background`.

#### `tooltip` — hint wrapper

Props: `text`, `position`, `visible`, `delay`.

### 4.2 Leaves

#### `text`

```elixir
text "Hello, world!"
text "Count: @count", text_size: :xl, text_color: :on_surface
text "Title", variant: :heading
text @api_key, selectable: true
```

Props: `text_color`, `text_size`, `font_weight` (`"bold"`, `"semibold"`, …),
`font_family`, `text_align` (`:left`/`:center`/`:right`), `italic`,
`line_height`, `letter_spacing`, `variant`
(`:display`,`:heading`,`:title`,`:body`,`:caption`,`:label`,`:overline`),
`selectable`, `padding*`, `background`, `corner_radius`, `fill_width`,
`on_tap`, `on_long_press`, `on_double_tap`.

#### `button`

```elixir
button "Press me", on_tap: :pressed
button "Submit", on_tap: :submit, background: :primary, disabled: false
```

Props: `on_tap`, `disabled`, `text_color`, `text_size`, `font_weight`,
`background`, `padding*`, `corner_radius`, `fill_width`, `variant`, `icon`,
`elevation`.

#### `icon_button`

Props: `icon`, `on_tap`, `selected`, `enabled`, `color`, `text_color`,
`background`, `size`, `disabled`.

#### `fab` — floating action button

Props: `icon`, `text`, `on_tap`, `background`, `color`, `elevation`,
`corner_radius`.

#### `icon`

```elixir
icon "settings", text_size: 24
icon "chevron_right", on_tap: :navigate
```

First positional arg = icon name. Props: `text_size`, `text_color`,
`padding`, `background`, `on_tap`, `on_long_press`.

#### `image`

```elixir
image "https://example.com/photo.jpg"
image "logo.png", width: 100, height: 100, resize_mode: :contain
```

First positional arg = URL/asset (`source`; `src` alias). Props:
`resize_mode` (`:cover`/`:contain`/`:stretch`/`:repeat`), `width`,
`height`, `corner_radius`, `placeholder_color`, `on_error`, `on_load`.

#### `video`

```elixir
video "https://example.com/clip.mp4", autoplay: true, loop: true
```

Props: `autoplay`, `loop`, `muted`, `controls`, `width`, `height`.

#### `text_field`

```elixir
text_field placeholder: "Enter name", on_change: :name_changed
text_field text: @email, keyboard_type: :email, secure: true, on_change: :email_changed
text_field placeholder: "Bio", max_lines: 4, on_change: :bio_changed
```

Current value binds via **`text:`** (there is no `value:` prop). Props:
`text`, `placeholder`, `on_change`, `on_focus`, `on_blur`, `on_submit`,
`on_compose`, `secure`, `keyboard_type`
(`:default`,`:number`,`:decimal`,`:email`,`:phone`,`:url`), `return_key`
(`:done`,`:next`,`:go`,`:search`,`:send`), `max_length`,
`auto_capitalize`, `auto_correct`, `min_lines`, `max_lines`, `disabled`,
`text_color`, `text_size`, `background`, `padding`, `corner_radius`.

#### `toggle` / `checkbox` / `radio` / `switch`

```elixir
toggle value: @on, on_change: :toggled, text: "Notifications"   # label prop is :text
checkbox value: @agreed, on_change: :agreed, label: "I agree"   # label prop is :label
radio selected: @choice == :a, on_select: :picked, label: "Option A", group: "choices"
switch value: true, on_toggle: :toggled        # legacy — prefer toggle
```

Toggle extras: `disabled`, `track_color`, `thumb_color`.

#### `slider`

```elixir
slider value: @volume, min_value: 0, max_value: 100, on_change: :volume_changed
```

Props: `value`, `min_value`, `max_value`, `on_change`, `color`.

#### Small utilities

```elixir
divider()
divider thickness: 2, color: :primary          # thickness/color/padding
spacer()                                        # flexible
spacer size: 20                                 # fixed (also :fixed_size)
activity_indicator size: :large, animating: true
progress_bar progress: 0.7
status_bar bar_style: :light_content            # bar_style/hidden/background
refresh_control on_refresh: :reload, refreshing: false   # tint_color too
```

#### Media & embeds

```elixir
webview "https://elixir-lang.org"
webview "https://example.com", show_url: true, allow: ["https://example.com"]
camera_preview facing: :front, width: 300, height: 400
native_view MyChartComponent, id: :revenue_chart     # id required
```

Webview props: `show_url`, `title`, `allow` (URL prefixes), `width`,
`height`.

#### Data-driven & navigation leaves

```elixir
list :history, data: @items, on_end_reached: :load_more,
  empty_text: "Nothing yet", separator: true

tab_bar tabs: [%{id: "home", label: "Home", icon: "home"}],
  active_tab: "home", on_tab_select: :tab_changed

carousel :slides, data: @slides, on_page_change: :page_changed

app_bar title: "Inbox", leading_icon: "back", on_leading: :back_pressed
nav_bar items: [%{id: "home", label: "Home", icon: "home"}], active: "home", on_select: :nav_changed
nav_rail items: [...], active: "home", on_select: :rail_changed
nav_drawer visible: @open, on_dismiss: :closed, items: [...], active: "home", on_select: :drawer_nav

segmented_button segments: [%{id: "day", label: "Day"}, %{id: "week", label: "Week"}],
  selected: "week", on_select: :range_changed

chip label: "Filter", variant: :filter, selected: true, on_tap: :chip_tapped
snackbar message: "Deleted", action_label: "Undo", on_action: :undo
menu items: [%{label: "Edit", action: :edit}], visible: @open, on_select: :menu_selected
date_picker visible: true, on_select: :date_picked, selected_date: "2025-01-15"
time_picker visible: true, on_select: :time_picked, selected_time: "09:30"
search_bar placeholder: "Search...", on_change: :search_changed, on_submit: :submitted
```

`list` takes its identifier as first argument (used for selection events);
data comes from `data:`/`items:` — there is no `scroll` bool.

#### States & feedback

```elixir
empty_state icon: "checkmark.circle",
  title: "All clear",
  message: "No tasks yet",
  action_label: "Add one",
  on_action: :add

skeleton                                    # shimmer placeholder
avatar "https://…/pic.jpg"                  # falls back to initials
stepper                                     # multi-step indicator
```

---

## 5. Event Handling

### Canonical shapes

| Event | Prop | Handler head |
|-------|------|---------------|
| Tap-style | `on_tap: :save` | `handle_event(:save, _params, socket)` |
| Parameterised tap | `on_tap: {:remove, id}` | `handle_event({:remove, id}, _params, socket)` |
| Value change | `on_change: :email_changed` | `handle_event(:email_changed, %{"value" => v}, socket)` |

Change events deliver `%{"value" => value}` in the params map. Legacy
`{:change, tag, value}` tuples are translated internally by
`Dala.Event.Bridge`; always match the forms above in new screens.

### Handler body contract

```elixir
def handle_event(:add_task, _params, socket) do
  {:noreply,
   socket
   |> Dala.Socket.assign(:tasks, socket.assigns.tasks ++ [new_task])
   |> Dala.Socket.assign(:draft, "")}
end
```

Return `{:noreply, socket}`. Changed assigns re-render automatically;
navigation actions come from the returned socket:

```elixir
{:noreply, Dala.Socket.push_screen(socket, MyApp.DetailScreen, %{id: id})}
{:noreply, Dala.Screen.pop_screen(socket)}
```

### handle_info/2

Device results (camera, location, tasks) and raw messages arrive here:

```elixir
def handle_info({:camera, :photo, %{path: path}}, socket) do
  {:noreply, Dala.Socket.assign(socket, :photo_path, path)}
end
```

Missing handlers warn during `mix compile` (after-verify hook) and raise
loudly at runtime if actually triggered.

---

## 6. Common Patterns

### 6.1 Counter screen

```elixir
defmodule MyApp.CounterScreen do
  use Dala.Spark.Dsl

  attributes do
    attribute :count, :integer, default: 0
  end

  screen name: :counter do
    column padding: 16, gap: 12 do
      text "Count: @count", text_size: :xl
      row gap: 8 do
        button "-", on_tap: :decrement
        button "+", on_tap: :increment
      end
    end
  end

  def handle_event(:increment, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_event(:decrement, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count - 1)}
  end
end
```

### 6.2 Form screen

```elixir
defmodule MyApp.FormScreen do
  use Dala.Spark.Dsl

  attributes do
    attribute :name, :string, default: ""
    attribute :email, :string, default: ""
    attribute :submitting, :boolean, default: false
  end

  screen name: :form do
    scroll padding: 16 do
      column gap: 12 do
        text "Contact Form", text_size: :xl, font_weight: "bold"
        text_field placeholder: "Name", text: @name, on_change: :name_changed
        text_field placeholder: "Email", text: @email, keyboard_type: :email, on_change: :email_changed
        button "Submit", on_tap: :submit, disabled: @submitting
      end
    end
  end

  def handle_event(:name_changed, %{"value" => v}, socket),
    do: {:noreply, Dala.Socket.assign(socket, :name, v)}

  def handle_event(:email_changed, %{"value" => v}, socket),
    do: {:noreply, Dala.Socket.assign(socket, :email, v)}

  def handle_event(:submit, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :submitting, true)}
  end
end
```

### 6.3 Keyed list with per-row actions

```elixir
defmodule MyApp.TasksScreen do
  use Dala.Spark.Dsl

  attributes do
    attribute :tasks, :list, default: []
  end

  defui task_row(task) do
    row gap: 8, alignment: :center do
      checkbox value: task.done, on_change: {:toggle_task, task.id}, label: task.title
      icon_button icon: "trash", on_tap: {:remove_task, task.id}
    end
  end

  screen name: :tasks do
    column gap: 12 do
      for task <- @tasks, id: task.id do
        task_row(task)
      end
    end
  end

  def handle_event({:toggle_task, id}, %{"value" => done}, socket) do
    tasks =
      Enum.map(socket.assigns.tasks, fn t ->
        if t.id == id, do: Map.put(t, :done, done), else: t
      end)

    {:noreply, Dala.Socket.assign(socket, :tasks, tasks)}
  end

  def handle_event({:remove_task, id}, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :tasks, Enum.reject(socket.assigns.tasks, &(&1.id == id)))}
  end
end
```

### 6.4 Conditional loading state

```elixir
if @loading do
  activity_indicator size: :large
else
  button "Load more", on_tap: :load_more
end
```

### 6.5 Safe area with scrollable content

```elixir
screen name: :scrollable do
  safe_area do
    scroll padding: 16 do
      text "@content"
    end
  end
end
```

---

## 7. Registration in Dala.App

```elixir
defmodule MyApp do
  use Dala.App

  def navigation(_platform) do
    screens([MyApp.HomeScreen, MyApp.DetailScreen])
    stack(:home, root: MyApp.HomeScreen)
  end
end
```

`screens/1` validates each module at compile time. `stack/2` declares the
stack root; combine stacks under `tab_bar/1` or `drawer/1` for shells.

---

## 8. Compile-Time Guarantees

| You write | You get | Level |
|-----------|---------|-------|
| Prop not in the component's registry entry | `unknown prop :weight on :text. Did you mean :font_weight?` | **Error** — build fails |
| Prop-call inside a container | `:gap is a prop of :column … pass it as a keyword argument` | **Error** |
| Unknown component name | `Unknown component :buttn …` + suggestion | **Error** |
| Condition that isn't ref/literal/compute | guidance to wrap in `compute/1` | **Error** |
| Attribute type outside the seven allowed | invalid-type message | **Error** |
| Leaf given children | leaf-does-not-accept-children message | **Error** |
| `@typo` not among declared attributes | warning listing declared refs | Warning |
| `on_tap: :nope` with no clause | missing-handler message after compile | Warning |
| Handler defined but never referenced | unused-handler info | Info |

Diagnostics carry real line numbers. Post-compile re-checks:

```bash
mix dala.verify --dsl [--strict]     # CI gate (--strict fails on warnings)
mix dala.verify --components         # print catalogue
mix dala.verify --components --markdown-output COMPONENTS.md   # generated reference
```

---

## 9. Generated Functions

Never write these by hand in a DSL screen:

### mount/3

Initialises every attribute to its default (always generated):

```elixir
def mount(_params, _session, socket) do
  socket = Dala.Socket.assign(socket, :count, 0)
  {:ok, socket}
end
```

### render/1

Builds node maps from the screen block:

```elixir
def render(assigns) do
  [
    %{type: :column, props: %{gap: :space_sm}, children: [
      %{type: :text, props: %{text: "Count: " <> to_string(assigns[:count])}, children: []}
    ]}
  ]
end
```

---

## 10. Migration from Manual Screens

| Manual | DSL |
|--------|-----|
| `use Dala.Screen` | keep, or `use Dala.Spark.Dsl` directly |
| Manual `mount/3` assigns | `attribute :key, :type, default: val` lines |
| Manual `render/1` widget calls | `screen do … end` block |
| `Dala.Ui.Widgets.text(text: "Hello")` | `text "Hello"` |
| `Dala.Ui.Widgets.column([gap: 8], [...])` | `column gap: 8 do … end` |
| `handle_event/3` / `handle_info/2` | unchanged |

Steps: move mounts → attributes; translate render body → screen block;
delete both functions; compile — strictness flags anything mistranslated.

---

## 11. Anti-Patterns to Avoid

| Anti-pattern | Why | Fix |
|-------------|-----|-----|
| Writing `mount/3` or `render/1` manually | Clashes with generated versions | Use `attributes do` / `screen do` |
| Prop calls inside containers (`column do gap 8 end`) | Compile error with hint | Keyword args: `column gap: 8 do` |
| Inventing props (`weight:`, `color:` on text) | Compile error with Did-you-mean | Registry names: `font_weight:`, `text_color:` |
| `text_field value: x` | No such prop — silently-bound state never shows | `text_field text: x` |
| `on_tap: "save"` (string) | Compile error — handlers are atoms | `on_tap: :save` |
| Complex conditions (`Map.get(@x,:k)==nil`) | Compile error | Wrap in `compute(fn assigns -> … end)` |
| Unkeyed `for` over editable rows | Whole-list rebuilds on change | Add `id: item.id` |
| Undeclared `@ref` | Warns; renders empty until declared | Declare the attribute |
| `dala do … end` wrapper | Deprecated | Flat sections |

---

## 12. Quick-Reference Checklist

When generating a new screen module, verify:

- [ ] `use Dala.Spark.Dsl` at the top
- [ ] Flat sections: `attributes do … end`, then `screen name: :atom do … end`
- [ ] Container props as keyword arguments on the container call
- [ ] Leaf content positional, everything else keyword props
- [ ] Every prop exists in the registry (typos fail the build)
- [ ] Value components bind via `text:` / `value:` / etc. exactly as tabled
- [ ] Every `@ref` matches a declared attribute (or `@safe_area`)
- [ ] Conditions are refs, literals, or `compute/1`
- [ ] Keyed `for` loops for editable collections
- [ ] One `handle_event/3` clause per referenced event atom (incl. tuples)
- [ ] No manual `mount/3` / `render/1`
- [ ] Registered in `Dala.App.navigation/1` via `screens/1`
