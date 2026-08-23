# Spark DSL Guide

The Spark DSL lets you define Dala screens declaratively — state as
attributes, UI as a tree of components — instead of hand-writing `mount/3`
and `render/1`. Everything is checked at compile time against the component
registry, so typos fail the build instead of silently rendering wrong UI.

This guide has three parts:

1. **[Mental model](#mental-model)** — how the DSL works, in one page.
2. **[Quick start](#quick-start-your-first-screen)** and
   **[Tutorial](#tutorial-a-task-list-screen)** — build real screens step by step.
3. **[Reference](#reference)** — every feature in detail, plus compiler
   guarantees, troubleshooting, and migration.

## Mental model

A screen module has three parts:

```elixir
defmodule MyApp.CounterScreen do
  use Dala.Spark.Dsl

  # 1. STATE — what the screen remembers
  attributes do
    attribute :count, :integer, default: 0
  end

  # 2. VIEW — how the screen looks, as a function of that state
  screen name: :counter do
    column padding: 16, gap: 12 do
      text "Count: @count", text_size: :xl
      button "+", on_tap: :increment
    end
  end

  # 3. LOGIC — how events change state
  def handle_event(:increment, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end
end
```

From these the DSL generates two functions you never write by hand:

| Generated | From | Does |
|-----------|------|------|
| `mount/3` | `attributes do` | Initialises every attribute to its default |
| `render/1` | `screen do` | Builds the UI node tree from current assigns |

The runtime loop is the same as Phoenix LiveView: an event arrives → your
`handle_event/3` updates assigns → changed keys trigger a re-render → the
diff engine patches only what changed on the native side. You never touch
views, adapters, or encoders.

**The compile-time contract:** every prop you pass must exist in the
component registry (`Dala.Ui.Component`) — unknown props are *compile
errors* with Did-you-mean suggestions. Every `@ref` should match a declared
attribute — undeclared ones warn. Every event atom should have a matching
`handle_event/3` clause — missing ones warn during `mix compile`.

---

## Quick start: your first screen

### Step 1 — Create the module

```elixir
# lib/my_app/screens/hello_screen.ex
defmodule MyApp.HelloScreen do
  use Dala.Spark.Dsl
end
```

`use Dala.Spark.Dsl` imports all component macros and registers the
compile-time checks. (`use Dala.Screen` also works — it delegates here and
adds the `Dala.Screen` behaviour.)

### Step 2 — Declare state

```elixir
defmodule MyApp.HelloScreen do
  use Dala.Spark.Dsl

  attributes do
    attribute :name, :string, default: "world"
  end
end
```

Each attribute becomes an assign, initialised automatically. Omitting
`default:` initialises to `nil`.

### Step 3 — Describe the UI

```elixir
  screen name: :hello do
    column padding: 24 do
      text "Hello @name!", text_size: :display
      button "Say hi", on_tap: :greet
    end
  end
```

Two syntax rules to internalise now:

- **Containers take keyword-arg props**: `column padding: 24 do ... end`.
- **Leaves take positional content + keyword props**: `text "…", text_size: :xl`.

### Step 4 — Handle the event

```elixir
  def handle_event(:greet, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :name, "Dala")}
  end
```

Return `{:noreply, socket}`. Any assign change re-renders automatically.

### Step 5 — Register and run

```elixir
defmodule MyApp do
  use Dala.App

  def navigation(_platform) do
    screens([MyApp.HelloScreen])
    stack(:home, root: MyApp.HelloScreen)
  end
end
```

Then deploy:

```bash
mix dala.push          # BEAM-only push (fast path while iterating)
Dala.Test.screen(:"my_app_ios@127.0.0.1")   # → MyApp.HelloScreen
```

That's the whole cycle. The tutorial below adds conditionals, lists,
derived values, and reusable components on top of it.

---

## Tutorial: a task list screen

We'll build a task list with input, add/remove, and a done toggle. Each step
compiles on its own — run `mix compile` after each one.

### Step 1 — Model the state

```elixir
defmodule MyApp.TasksScreen do
  use Dala.Spark.Dsl

  attributes do
    attribute :tasks, :list, default: []
    attribute :draft, :string, default: ""
  end
end
```

Rules of thumb: collections are `:list`, form inputs mirror their text field
in a `:string`, flags are `:boolean`.

### Step 2 — Static skeleton

```elixir
  screen name: :tasks do
    safe_area do
      scroll padding: 16 do
        app_bar title: "Tasks"

        column gap: 12 do
          text "Nothing yet", text_color: :on_surface_variant
        end
      end
    end
  end
```

Nesting recipe used everywhere below: `safe_area` → `scroll` → content
`column`s. `app_bar` gives you the header for free.

### Step 3 — Render each task with `for`

Replace the placeholder column with:

```elixir
        column gap: 12 do
          if compute(fn assigns -> assigns[:tasks] == [] end) do
            empty_state icon: "checkmark.circle",
              title: "All clear",
              message: "No tasks yet — add one below"
          end

          for task <- @tasks, id: task.id do
            row gap: 12, alignment: :center do
              checkbox value: task.done,
                on_change: {:toggle_task, task.id},
                label: task.title

              icon_button icon: "trash", on_tap: {:remove_task, task.id}
            end
          end
        end
```

Notes:

- Tasks are atom-keyed maps (`%{id: 1, title: "...", done: false}`) so both
  `task.done` field access and the keyed `id: task.id` work.
- The `for` source must be an `@ref`, a literal list, or a `compute/1`
  expression — arbitrary expressions like `Enum.with_index(@items)` are not
  evaluated here.
- Handlers may be atoms **or `{atom, argument}` tuples** — the tuple arrives
  at `handle_event/3` unchanged, which is how we tell *which* row fired.
- `id: task.id` gives each row a stable identity so updates patch one row
  instead of rebuilding the list.

### Step 4 — Add the input row

Above the tasks column:

```elixir
        row gap: 8, alignment: :center do
          text_field placeholder: "New task",
            text: @draft,
            on_change: :draft_changed

          icon_button icon: "plus.circle.fill", on_tap: :add_task
        end
```

### Step 5 — Wire the handlers

```elixir
  def handle_event(:draft_changed, %{"value" => value}, socket) do
    {:noreply, Dala.Socket.assign(socket, :draft, value)}
  end

  def handle_event(:add_task, _params, socket) do
    draft = String.trim(socket.assigns.draft || "")

    if draft == "" do
      {:noreply, socket}
    else
      task = %{id: System.unique_integer([:positive]), title: draft, done: false}

      {:noreply,
       socket
       |> Dala.Socket.assign(:tasks, socket.assigns.tasks ++ [task])
       |> Dala.Socket.assign(:draft, "")}
    end
  end

  def handle_event({:toggle_task, id}, %{"value" => done}, socket) do
    tasks =
      Enum.map(socket.assigns.tasks, fn task ->
        if task.id == id, do: Map.put(task, :done, done), else: task
      end)

    {:noreply, Dala.Socket.assign(socket, :tasks, tasks)}
  end

  def handle_event({:remove_task, id}, _params, socket) do
    tasks = Enum.reject(socket.assigns.tasks, &(&1.id == id))
    {:noreply, Dala.Socket.assign(socket, :tasks, tasks)}
  end
```

Change events deliver their payload as `%{"value" => value}`; taps usually
carry an empty map unless the component sends more.

### Step 6 — Verify from your terminal

```bash
mix dala.push
```

```elixir
node = :"my_app_ios@127.0.0.1"
Dala.Test.screen(node)                    # → MyApp.TasksScreen
Dala.Test.assigns(node)                   # → %{tasks: [], draft: ""}
Dala.Test.send_message(node, :ignored)    # drive it via taps once deployed
mcp__ios_simulator__screenshot            # visual check, when layout matters
```

Prefer `Dala.Test.*` over screenshots for state questions — it reads the
BEAM directly, exact and fast.

### Step 7 — Extract repeated pieces with `defui`

The task row will grow; keep the loop readable:

```elixir
  defui task_row(task) do
    row gap: 12, alignment: :center do
      checkbox value: task.done,
        on_change: {:toggle_task, task.id},
        label: task.title

      icon_button icon: "trash", on_tap: {:remove_task, task.id}
    end
  end
```

…and collapse the call site:

```elixir
          for task <- @tasks, id: task.id do
            task_row(task)
          end
```

`defui` bodies support the full DSL. Define them **above first use**, in the
same module.

You now have every core feature in one screen. The rest of this guide is
reference material.

---

## Reference

## Attributes

```elixir
attributes do
  attribute :count, :integer, default: 0
  attribute :query, :string, default: ""
  attribute :enabled, :boolean, default: true
  attribute :ratio, :float, default: 0.5
  attribute :mode, :atom, default: :idle
  attribute :items, :list, default: []
  attribute :meta, :map, default: %{}
  attribute :token, :string            # defaults to nil
end
```

- Types: `:integer`, `:string`, `:boolean`, `:float`, `:atom`, `:list`,
  `:map`. Anything else fails compilation.
- The block generates `mount/3`; **do not define `mount/3` yourself**.
- An `attributes` block without a `screen` still compiles (useful mid-refactor).
- Assigns set outside the block (e.g. in `handle_info`) work fine — they just
  don't get automatic defaults.

## The screen block

```elixir
screen name: :tasks do
  ...
end
```

- `name:` identifies the screen for navigation and debugging. Omit it and it
  is inferred: `MyApp.TasksScreen` → `:tasks` (suffixes `Screen`, `View`,
  `Page` are stripped, then snake_cased). A module without `name:` and
  without inference-friendly naming raises at compile time — name it or
  pass `name:` explicitly.
- Top-level entries become the children of the screen's root container.
- The old `dala do ... end` wrapper is deprecated but still compiles.

## Containers

Props are keyword arguments on the call; children go inside `do...end`.
Prop-call style inside the block (`column do gap 8 end`) is a compile error
with a hint.

| Component | Purpose | Notable props |
|-----------|---------|---------------|
| `column` | Vertical stack (VStack) | `padding*`, `gap`, `spacing`, `background`, `corner_radius`, `fill_width/height`, `alignment`, `cross_alignment`, `on_tap` |
| `row` | Horizontal stack (HStack) | same as column |
| `box` | Overlap / ZStack, sized boxes | `width`, `height`, `min_*`, `max_*`, `alignment` |
| `scroll` | Scrollable region | `direction`, `shows_indicator`, `padding`, `background`, `on_scroll` |
| `safe_area` | Notch/home-indicator insets | `edges`, `background` |
| `modal` | Modal overlay | `visible`, `on_dismiss`, `presentation_style` |
| `bottom_sheet` | Draggable sheet | `visible`, `on_dismiss`, `drag_indicator` |
| `pressable` | Tappable wrapper | `on_press`, `on_long_press`, `disabled` |
| `card` | Elevated surface | `variant`, `elevation`, `corner_radius` |
| `grid` | Grid layout | `columns`, `gap`, `row_gap` |
| `badge` | Notification dot wrapper | `count`, `color`, `position` |
| `tooltip` | Hover/long-press hint | `text`, `position`, `visible` |

All containers accept the accessibility props (`accessibility_id`,
`accessibility_label`, …).

## Leaves

Positional first argument carries the primary content where one exists
(`text`, `button`, `icon`, `image`, `video`, `webview`); everything else is
keyword props.

```elixir
text "Title", variant: :heading          # :display :heading :title :body :caption :label :overline
text "@name", selectable: true           # user-copyable
button "Save", on_tap: :save, disabled: @busy
icon "trash", text_size: 20, on_tap: :delete
image "https://…/pic.jpg", resize_mode: :cover, corner_radius: 12
text_field text: @email, keyboard_type: :email, on_change: :email_changed
toggle value: @notifications, on_change: :toggled, text: "Notifications"   # label prop is :text
checkbox value: @agreed, on_change: :agreed, label: "I agree"              # label prop is :label
slider value: @volume, min_value: 0, max_value: 100, on_change: :volume
divider()
spacer size: 20
activity_indicator size: :large, animating: true
progress_bar progress: 0.7
list :history, data: @history, on_end_reached: :load_more, empty_text: "Nothing yet"
native_view MyChart, id: :revenue         # platform-native component
```

For the full per-component prop list, generate the reference from the
registry rather than trusting prose:

```bash
mix dala.verify --components --markdown-output COMPONENTS.md
```

Unknown props fail the build with a suggestion, so drift between docs and
code can't hide anymore.

## State in the UI: `@ref`

Three positions:

```elixir
text "Count: @count"          # interpolated into any string prop
button "@confirm_label"       # whole-string ref
slider value: @volume         # bare ref in any prop position
```

- Refs resolve against the declared **attributes** plus the framework-provided
  `@safe_area` map.
- A ref that matches no attribute emits a **compile warning** ("renders
  empty") — fix the typo or declare the attribute.
- Bare *variables* are rejected with a hint (`text mystery` → use
  `@mystery`). Loop variables are exempt inside their `for` block.

## Conditional UI

```elixir
if @loading do
  activity_indicator size: :large
else
  text "Ready"
end

unless @archived do
  button "Delete", on_tap: :delete
end
```

- Conditions accept: an attribute ref (`@loading`), a literal, or a
  `compute(fn assigns -> ...)` expression.
- Complex expressions (`Map.get(@x, :k) == nil`) are rejected at compile time
  with guidance — wrap them in `compute/1`.
- Branches hold full DSL content and splice into the parent's children;
  both branches are optional.

## Lists

```elixir
for item <- @items do
  text item.label
end

for item <- @items, id: item.id do
  task_row(item)
end
```

- Inside the block, the loop variable is usable directly (`text item`) and
  single-level field access works (`item.label`) on atom-keyed maps/structs.
- **Key your loops** (`id:`) whenever rows change independently — keyed rows
  get stable ids so the diff engine patches individual rows instead of
  rebuilding the list.
- The `<-` source must be an `@ref`, a literal list, or a `compute/1`
  expression; arbitrary expressions are not evaluated.
- Nested loops exist but outer variables don't cross inner boundaries
  (compile error).

## Reusable pieces: `defui`

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

- Same module only, defined **above first use** (the parser resolves calls
  at compile time).
- Positional args only; wrong arity fails compilation.
- Bodies see caller `@ref`s and the full DSL.
- `defui` params can't cross a `for` boundary — compute values before the
  loop or read them from the item.

## Derived values: `compute/1`

Any 1-arity function in a prop position runs with live assigns at render time:

```elixir
text text: compute(fn assigns ->
      case assigns[:score] do
        nil -> "—"
        s -> "#{s} pts"
      end
    end),
  text_color: compute(fn assigns -> (assigns[:score] || 0) > 50 && :success || :error end)
```

Use it for formatting, derived colours, and conditions that need more than a
bare ref. It replaces the old pattern of pre-computing display strings in
handlers.

## Events

```elixir
button "Save", on_tap: :save                     # → handle_event(:save, params, socket)
icon_button on_tap: {:delete, id}                # → handle_event({:delete, id}, params, socket)
text_field on_change: :email_changed             # → %{"value" => value} in params
```

Canonical shapes:

| Event | Handler head |
|-------|--------------|
| Tap-style | `handle_event(:save, _params, socket)` |
| Parameterised tap | `handle_event({:delete, id}, _params, socket)` |
| Value change | `handle_event(:email_changed, %{"value" => v}, socket)` |

Legacy `{:change, tag, value}` tuples are translated internally by
`Dala.Event.Bridge`; new code matches the forms above. Missing clauses warn
at compile time and raise loudly at runtime if actually triggered.

Navigation actions return from handlers:

```elixir
def handle_event(:open, _p, socket),
  do: {:noreply, Dala.Socket.push_screen(socket, MyApp.DetailScreen, %{id: 7})}

def handle_event(:back, _p, socket),
  do: {:noreply, Dala.Screen.pop_screen(socket)}
```

## Live data: PubSub

```elixir
pubsub do
  subscribe "chat:room:123", on_message: :handle_chat
end

def handle_chat({:message, text}, socket) do
  messages = socket.assigns.messages ++ [text]
  {:noreply, Dala.Socket.assign(socket, :messages, messages)}
end
```

Subscriptions attach on mount and detach on terminate.

## Compile-time guarantees

| You write | You get | Level |
|-----------|---------|-------|
| Prop not in the component's registry list | `unknown prop :weight on :text. Did you mean :font_weight?` | **Error** (build fails) |
| Prop-call inside a container (`column do gap 8 end`) | `:gap is a prop of :column … pass it as a keyword argument` | **Error** |
| Unknown component name | `Unknown component :buttn …` | **Error** |
| Condition that isn't a ref/literal/compute | guidance to wrap in `compute/1` | **Error** |
| Attribute type outside the seven allowed | invalid-type message | **Error** |
| `@typo` not among declared attributes | `@typo is not a declared attribute … renders empty` | Warning |
| `on_tap: :nope` with no clause | missing-handler message after compile | Warning |
| `handle_event(:x)` never referenced from UI | unused-handler info | Info |

Line numbers point at the offending line. `mix dala.verify --dsl` re-runs
everything post-compile (`--strict` fails CI on warnings);
`mix dala.verify --components` prints the catalogue.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Screen shows nothing | `start_root` error swallowed, or every top-level node dropped | Pattern-match `{:ok, _} = Dala.Screen.start_root(...)`; run `mix dala.verify --dsl` |
| Text shows blank where data should be | Undeclared `@ref` | Check the compile warning; declare the attribute |
| Toggle/input doesn't show current value | Wrong prop name (`value:` vs `text:`) | Registry-checked now — read the compile error |
| Changes don't re-render | Handler returned `socket` unwrapped, or assigned nothing | Return `{:noreply, socket}`; assign via `Dala.Socket.assign/3` |
| Whole list rebuilds on each keystroke | Unkeyed `for` | Add `id: item.id` |
| Old syntax errors after upgrade | Pre-strictness examples (`dala do`, prop-calls) | Follow the Migration section |

## Migration from manual screens

1. Swap `use Dala.Screen` → `use Dala.Spark.Dsl` (or keep it; both include the DSL).
2. Move each `Dala.Socket.assign(socket, key, default)` in `mount/3` to an
   `attribute :key, :type, default: ...` line; delete `mount/3`.
3. Translate the widget-tree calls in `render/1` into `screen do` syntax;
   delete `render/1`.
4. Keep `handle_event/3` and `handle_info/2` as-is.

### Before

```elixir
defmodule MyApp.Counter do
  use Dala.Screen

  def mount(_params, _session, socket) do
    {:ok, Dala.Socket.assign(socket, :count, 0)}
  end

  def render(assigns) do
    Dala.Ui.Widgets.column([padding: :space_md, gap: :space_sm], [
      Dala.Ui.Widgets.text(text: "Count: #{assigns.count}"),
      Dala.Ui.Widgets.button(text: "Increment", on_tap: :increment)
    ])
  end

  def handle_event(:increment, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end
end
```

### After

```elixir
defmodule MyApp.Counter do
  use Dala.Spark.Dsl

  attributes do
    attribute :count, :integer, default: 0
  end

  screen name: :counter do
    column padding: :space_md, gap: :space_sm do
      text "Count: @count"
      button "Increment", on_tap: :increment
    end
  end

  def handle_event(:increment, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
  end
end
```

## App integration

Register screens once; `screens/1` validates them at compile time:

```elixir
def navigation(_platform) do
  screens([MyApp.HelloScreen, MyApp.TasksScreen])
  stack(:home, root: MyApp.HelloScreen)
end
```

Tabbed shells combine stacks under `tab_bar/1`; drawers under `drawer/1`.
