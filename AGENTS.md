# AGENTS.md — orientation for AI agents working on Dala

You're in the **dala** repo, the runtime library for the Dala dalaile framework.
Read this in full before making changes — it's the 5-minute orientation that
will keep you from re-deriving things the rest of the team has already learned
(or learned the hard way).

## What Dala is, in one paragraph

Dala lets you write iOS and Android apps in Elixir, with the BEAM running
on-device. The phone hosts an Erlang node — a real one, distribution-capable,
introspectable, hot-code-loadable. Two modes: a SwiftUI/Compose UI driven by
Elixir GenServers (Dala UI apps), or a sidecar BEAM embedded in a normal native
app to give agents and tests live access (Dala as test harness). The sidecar
mode is the long-term bet. Both modes produce a real Erlang node you can `Node.connect/1` to.

For the *why* (the BEAM-on-dalaile pitch), see `guides/why_beam.md`.

## Repo topology

Dala is three coordinated repos. **Know which one to edit before you change anything.**

| Repo | Path | What lives here | Edit when |
|---|---|---|---|
| **dala** | `~/code/dala` | Runtime library: `Dala.Screen`, `Dala.App`, `Dala.Renderer`, `Dala.Dist`, `Dala.Test`, **`Dala.Designer` dev tool**, the iOS Swift / Android Kotlin native bridges, the NIF | UI behavior, on-device runtime, native bridge changes, **dev tooling** |
| **dala_dev** | `~/code/dala_dev` | Mix tasks: `dala.deploy`, `dala.connect`, `dala.devices`, `dala.emulators`, `dala.provision`, `dala.doctor`, `dala.battery_bench_*`. Device discovery (`DalaDev.Discovery.{Android,IOS}`). Native build orchestration (`DalaDev.NativeBuild`). OTP tarball download/cache (`DalaDev.OtpDownloader`). | Build/deploy mechanics, device handling, dev tooling |
| **dala_new** | `~/code/dala_new` | Project generator. Hex archive (`mix archive.install hex dala_new`). Templates in `priv/templates/dala.new/`. Generates both native Dala UI projects and Phoenix LiveView wrappers. | Generator output for new projects |

Cross-repo changes are common — fixing one user-visible behavior often needs
the runtime patched in `dala`, the build retooled in `dala_dev`, **and** the
generator template updated in `dala_new` so newly-generated projects pick up
the fix without manual edits.

The OTP runtime tarballs (Android arm64/arm32, iOS sim, iOS device) are built
separately and uploaded to GitHub Releases — see `dala_dev/build_release.md`
and `dala_dev/scripts/release/`. Patches we apply to OTP source live at
`dala_dev/scripts/release/patches/`.

## Driving apps from your session

The default instinct — screenshots — is wrong. Dala apps run a real Erlang node
you can talk to directly. Read the BEAM, drive it, then verify visually only
when state isn't enough.

### Connect

```bash
mix dala.devices                 # list everything connected (sims, emulators, physical)
mix dala.emulators --list        # list virtual devices (running and stopped)
mix dala.connect                 # set up tunnels, start IEx attached to all running nodes
mix dala.connect --no-iex        # just print node names + tunnels (for scripting)
```

Node names are platform-specific:

```
dala_demo_ios@127.0.0.1                     # iOS simulator
dala_demo_android_<serial-suffix>@127.0.0.1  # Android (suffix from ro.serialno)
```

For iOS simulator, the sim shares the Mac's network stack — distribution Just
Works. For Android (and iOS device), `mix dala.connect` sets up `adb reverse` /
similar tunnels.

### Inspect (`Dala.Test`, BEAM-state, fast, exact — prefer this)

```elixir
node = :"dala_demo_ios@127.0.0.1"

Dala.Test.screen(node)            # which screen is showing?  → ModuleName
Dala.Test.assigns(node)           # live socket assigns        → %{...}
Dala.Test.find(node, "Submit")    # locate widget by visible text
Dala.Test.inspect(node)           # full snapshot: screen, assigns, nav stack, widget tree
```

This is faster, exact (not pixel-inferred), and works without taking a
screenshot. Use it as the default.

### Drive

```elixir
Dala.Test.tap(node, :open_text)              # tap by tag atom (the on_tap: {self(), :tag})
Dala.Test.send_message(node, {:custom, :msg}) # arbitrary handle_info
```

After a tap, call `Dala.Test.screen(node)` again to confirm navigation
happened. Call `Dala.Test.assigns(node)` to confirm state changed.

### Visual verify (MCP, slower, image-based — only when needed)

When layout/animation/rendering matters, fall back to MCP platform tools:

| iOS simulator | Android |
|---|---|
| `mcp__ios-simulator__screenshot` | `mcp__adb__dump_image` |
| `mcp__ios-simulator__ui_view` | `mcp__adb__inspect_ui` |
| `mcp__ios-simulator__ui_tap {x, y}` | `adb shell input tap` |
| `mcp__ios-simulator__ui_swipe` | `adb shell input swipe` |
| `mcp__ios-simulator__record_video` | `adb shell screenrecord` |

Use these to confirm a layout looks right, spot animation glitches, or
debug rendering. **Don't use them for state queries** — `Dala.Test.assigns/1`
is always better.

### Round-trip workflow

```
1. Edit Elixir/Swift/Kotlin code
2. mix dala.push                  # fast: BEAM-only push, no native rebuild
   mix dala.deploy --native       # slower: native rebuild needed (NIF / Swift / Kotlin change)
3. Dala.Test.screen(node)         # confirm navigation / state
4. mcp__*__screenshot            # spot-check visual (only if layout matters)
5. Dala.Test.tap(node, :button)   # drive next interaction
6. Dala.Test.assigns(node)        # confirm state updated
7. repeat
```

Full workflow detail: `guides/agentic_coding.md`.

## Pre-empt-failure rules — read before you touch anything

These are the things we've burned ourselves on. Following them isn't optional.

1. **Default arguments evaluate eagerly.** `System.get_env("ROOTDIR", Path.expand("~/..."))`
   evaluates `Path.expand` *every call*, regardless of whether `ROOTDIR` is set.
   `Path.expand("~/...")` calls `System.user_home!()` which raises on Android
   (no `HOME` env var). Use `case System.get_env(...)` or `||` instead. Burned us
   once — see commit `d77932e`.

2. **Don't silently swallow `Dala.Screen.start_root` errors.** It returns
   `{:ok, pid}` or `{:error, reason}` and crashes from inside `init` are reported
   via `{:error, ...}`. If you don't pattern-match, the screen never renders and
   the app sits on the "Starting BEAM…" splash forever. The on_start callback
   should `{:ok, _} = Dala.Screen.start_root(...)` so failures crash loudly.

3. **TDD discipline in dala_dev.** Every new public function gets a test.
   `dala_dev/CLAUDE.md` makes this explicit. Don't bypass — the tests are how we
   catch the multi-step regressions like the iOS-device deploy chain.

4. **Format + credo before commit.** `mix format && mix credo --strict` from the
   relevant repo, every time. Both are clean across the codebase today; don't
   regress them.

5. **Multi-repo changes batch together.** A user-visible fix in dala often needs
   matching changes in dala_dev (build) and dala_new (template). Bumping versions
   without coordination produces ghost regressions. Check all three before
   declaring done.

6. **iOS device sandbox blocks `fork()`.** The BEAM's `forker_start` and EPMD's
   `run_daemon` both call fork; both are patched in our OTP cross-compile.
   Patches at `dala_dev/scripts/release/patches/`. Don't undo them.

7. **iOS sim and iOS device are different build paths.** Sim → `ios/build.sh`
   (`build_ios/1` in NativeBuild). Device → `ios/build_device.sh`
   (`build_ios_physical/2`). When `--device <udid>` is passed, dala_dev resolves
   it via `IOS.list_devices/0` to know which path to take. Don't shortcut.

8. **LV port 4200 is global per device.** Two installed Dala LV apps + one
   running = the second can't bind. Workaround for now: force-stop the squatter.
   Real fix tracked in `issues.md` #4 (hash bundle id into port).

9. **Compile-time `~r//` literals are unsafe on OTP 28.** They bake a
   `:re_exported_pattern` and call `:re.import/1` at runtime; OTP 28.0 removed
   that function. Use `Regex.compile!("...", "flags")` to compile at runtime.
   71 literals across dala_dev were swept in 0.3.17.

10. **`:dala_nif.log/1` for early startup logging, `Logger` after Dala.App.start.**
    `Dala.NativeLogger.install()` runs as part of `Dala.App.start` and reroutes
    `Logger` to NSLog/logcat. Before that point (steps 1–4 in the Erlang
    bootstrap), `Logger` output goes to stderr and is invisible. Use
    `:dala_nif.log("message")` for diagnostics during early init.

### 11. **UI render path: Elixir → Binary Protocol → Rust NIF → ObjC → SwiftUI.**
    The render pipeline now uses a **custom binary protocol** instead of JSON:
    - `Dala.Renderer.render/4` encodes `Dala.Node` trees to compact binary
    - `Dala.Renderer.encode_tree/1` handles full tree encoding
    - `Dala.Renderer.encode_frame/1` handles incremental patch encoding
    - `Dala.Native.set_root_binary/1` NIF receives binary data (replaces `set_root/1`)
    - Binary format: `[u16 version][u16 flags][u64 node_count] + nodes`
    - Patches: `[u16 version=1][u16 patch_count] + opcodes`
    - Zero-copy at boundary: Rustler's `Binary<'a>` maps directly to BEAM off-heap binaries
    - See `Dala.Renderer` module docs for full binary protocol spec.

12. **Skip renders when nothing changed (Strategy 1).**
    `Dala.Socket.assign/3` now tracks changed keys in `__dala__.changed`.
    `Dala.Socket` struct properly initializes `changed` in the struct definition
    (not just in `new/2`) so pattern matching always works.
    `Dala.Screen.do_render/3` skips the render if no assigns changed
    and no navigation occurred. This avoids unnecessary binary encoding +
    SwiftUI diffing for events that don't affect the UI.
    To force a render, use `Dala.Socket.changed?/2` to check if specific
    keys changed, or rely on navigation (push/pop/reset) which always renders.
    **Fixed 2025:** `do_render/3` now clears `changed` even when skipping
    render, preventing stale change tracking.

13. **Struct fields used in guards/pattern-matching must be initialized.**
    If a struct defines a field but doesn't set a default, code that
    accesses it with `socket.__dala__.changed` (instead of `[:changed]`)
    will fail when the field is missing. Always initialize all fields
    in the struct definition, not just in constructor functions.
    Burned us in `Dala.Socket` where `:changed` was only set in `new/2`.

## 14. **Zero-config ML on iOS/Android.**
    `Dala.ML.setup/0` auto-configures the ML stack for the platform:
    - iOS device: EMLX with Metal GPU, JIT disabled (W^X policy)
    - iOS simulator: EMLX with Metal GPU, JIT enabled
    - Android: Nx.BinaryBackend
    - Other: Nx.BinaryBackend
    No manual `config :nx, ...` or `config :emlx, ...` needed!
    CoreML predictions are synchronous (NIF captures ObjC callback result via Mutex)
    and run on the dirty CPU scheduler (`schedule = "DirtyCpu"`).
    ONNX NIFs are also dirty CPU scheduled and available on both iOS and Android.
    See `examples/ml_app/` for a ready-to-run YOLO detection app.

## 15. **WebView interact API for programmatic control.**
    `Dala.Ui.Embedded.Webview.interact/2` provides a high-level API for driving WebView
    content from Elixir, similar to `Dala.Test` but for production use.
    
    Available actions:
    - `{:tap, selector}` - Tap an element by CSS selector
    - `{:type, selector, text}` - Type text into input fields
    - `{:clear, selector}` - Clear input fields
    - `{:eval, js_code}` - Evaluate JS and get result via `handle_info({:webview, :eval_result, ...})`
    - `{:scroll, selector, dx, dy}` - Scroll elements programmatically
    - `{:wait, selector, timeout_ms}` - Wait for elements to appear
    
    Results arrive as `handle_info({:webview, :interact_result, %{"action" => ..., "success" => ...}}, socket)`.
    
    Also added: `navigate/2`, `reload/1`, `stop_loading/1`, `go_forward/1`
    for complete WebView navigation control.

## 16. **Spark DSL for declarative screens.**

    **Read [`skill-generate-screen-dsl.md`](skill-generate-screen-dsl.md) first** — it's guide for define screens by DSL with ui components, props.

    Dala supports a Spark DSL for defining screens declaratively. The DSL mirrors
    `Dala.Ui.Widgets` one-to-one — every component and prop available in `Dala.Ui.Widgets` has
    a DSL equivalent.

    ```elixir
    defmodule MyApp.CounterScreen do
      use Dala.Spark.Dsl

      attributes do
        attribute :count, :integer, default: 0
      end

      screen name: :counter do
        column gap: :space_sm do
          text "Count: @count"
          button "Increment", on_tap: :increment
        end
      end

      def handle_event(:increment, _params, socket) do
        {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
      end
    end
    ```

    **Syntax rules (enforced at compile time):**
    - **Container props are keyword args** — `column gap: :space_sm do`; prop-call style inside a container block (`column do gap :space_sm end`) is a compile error with a hint.
    - **Unknown props fail the build** — validated against `Dala.Ui.Component` at parse time with Did-you-mean suggestions; nothing is silently dropped.
    - **Flat sections** — `attributes do` + `screen name:` at module top level. The old `dala do ... end` wrapper is deprecated (still compiles).
    - **Screen-name inference** — omit `name:` to derive it from the module (`MyApp.FooScreen` → `:foo`). `attributes` without `screen` also compiles.

    Features:
    - **@ref syntax**: Use `@count` in strings to reference assigns. Undeclared refs emit compile warnings (they render empty). Refs must match a declared attribute or `@safe_area`.
    - **Control flow**: `if`/`unless`/`for` work in screen blocks and are expanded at render time (`Dala.Ui.List.expand`). Conditions accept `@refs`, literals, or `compute(fn assigns -> ...)`.
    - **Handler tracking**: missing/unused `handle_event` clauses warn during `mix compile` via `@after_verify` (`Dala.Spark.DslVerifier.handler_warnings/1`).
    - **Auto-generated mount/3**: Initializes attributes with defaults; always generated
    - **Leaf components**: text, button, icon, divider, spacer, text_field, toggle, slider,
      switch, image, video, activity_indicator, progress_bar, status_bar, refresh_control,
      webview, camera_preview, native_view, tab_bar, list, checkbox, radio, chip,
      snackbar, fab, icon_button, segmented_button, app_bar, nav_bar, nav_drawer,
      nav_rail, menu, date_picker, time_picker, search_bar, carousel, skeleton,
      empty_state, avatar, stepper
    - **Container components**: column, row, box, scroll, modal, pressable, safe_area,
      card, badge, bottom_sheet, tooltip, grid
    - **Container props as keyword args**: `column padding: :space_md, gap: :space_sm do ... end`
    - **Leaf props as keyword args**: `text "Hello", text_size: :xl`
    - **Conditional rendering**: `if @loading do ... else ... end` and `unless @show do ... end`
      inside screen blocks, desugared to `:conditional` nodes at compile time.
      `unless` bodies land in the conditional's ELSE branch (no negation AST).
    - **List rendering**: `for item <- @items, id: item.id do ... end` inside screen
      blocks; keyed rows get stable ids (`<parent>:item-<key>`) so the diff engine
      (rule #18) patches individual rows. Unkeyed loops fall back to content-hash ids.
    - **@ref in any prop position**: bare `@count` works in props (`text_size: @size`),
      not just inside strings. Bare loop vars work too (`text item` in a `for` block).
    - **compute/1 escape hatch**: `text_size: compute(fn assigns -> assigns[:big] && :xl || :sm end)`
      — any 1-arity fn prop is resolved with assigns at render time.
    - **defui local components**:
      ```elixir
      defui card_header(title) do
        row gap: :space_sm do
          text title, variant: :title
          spacer()
        end
      end
      ```
      Define above first use (same module only). Bodies support the full DSL;
      call sites splice the returned nodes as siblings; usable inside `for` blocks.
    - **Compile-time verification is strict**: unknown components and bad event
      handlers emit stderr compiler diagnostics AND raise — broken screens fail
      the build instead of rendering empty. Runtime `Dala.Spark.DslVerifier.verify_module/1`
      additionally flags defined-but-unreferenced handlers via beam debug_info.
    - **Text variants**: `text "Hello", variant: :heading` — presets for
      `:display`, `:heading`, `:title`, `:body`, `:caption`, `:label`, `:overline`
      (derived from `Dala.Ui.Widgets.variant_presets/0`, single source of truth)
    - **Text selectable**: `text @api_key, selectable: true` — allows user to copy text

    The extension module (`Dala.Spark.Dsl`) is both a Spark extension and a DSL
    module (`use Spark.Dsl, default_extensions: [extensions: __MODULE__]`).
    This means `use Dala.Spark.Dsl` sets up the full Spark DSL on the user module.

    See `guides/spark_dsl.md` for full documentation.

    ## New components (v0.8)
    - `:skeleton` — animated shimmer placeholder for loading states
    - `:empty_state` — icon + message + optional CTA for empty screens
    - `:avatar` — profile image with fallback initials
    - `:stepper` — multi-step indicator for forms/onboarding
    - `:grid` — grid layout container (LazyVerticalGrid / LazyVGrid)

    ## Accessibility props (v0.8)
    All components now accept `:accessibility_label`, `:accessibility_hint`,
    `:accessibility_role`, `:accessibility_value`, and `:accessibility_hidden`
    in addition to the existing `:accessibility_id` test identifier.

    ## Theme API additions (v0.8)
    - `Dala.Theme.resolve/1` — resolve a token to its current value
    - `Dala.Theme.set_accent/1` — override primary/on_primary with auto-contrast
    - `Dala.Theme.prefers_reduced_motion/0` — OS reduced-motion accessibility setting
    - `Dala.Theme.Adaptive.Custom.new/1` — custom adaptive theme with dark/light pair
    - Line-height tokens: `:line_height_tight`, `:line_height_normal`, `:line_height_relaxed`
    - Text variant presets: `:display`, `:heading`, `:title`, `:body`, `:caption`, `:label`, `:overline`

    ## Expanded icon set (v0.8)
    Logical icon names expanded from 28 to 104, covering bookmark, download,
    camera, notification, wifi, bluetooth, battery, play/pause, undo/redo, save,
    folder, file, zoom, fullscreen, expand/collapse, and many more.

    ## DSL verification (v0.8)
    `Dala.Spark.DslVerifier` provides comprehensive compile-time and runtime
    verification of DSL definitions. Warnings are emitted during `mix compile`
    for:
    - Unknown component types
    - Invalid prop names (with typo suggestions via Jaro-Windows distance)
    - Non-atom event handler values
    - Leaf components with children
    - Invalid attribute types
    - Invalid text variant values

    Run `mix dala.verify --dsl` for a full project scan, or
    `mix dala.verify --components` to list all available components.
    Use `mix dala.verify --dsl --strict` in CI to fail on warnings.

    Programmatic API: `Dala.Spark.Dsl.verify(module)` or `Dala.verify_dsl(module)`.
    Compile-time hook: `Dala.Spark.DslCompileHook` (auto-registered via `@before_compile`).
    Key files: `lib/dala/spark/dsl_verifier.ex`, `lib/dala/spark/dsl_compile_hook.ex`,
    `lib/mix/tasks/dala.verify.ex`.

## 17. **Dala.App screens/1 helper.**
    Use `screens/1` in your app's `navigation/1` to register screen modules:
    
    ```elixir
    def navigation(_) do
      screens([MyApp.HomeScreen, MyApp.SettingsScreen])
      stack(:home, root: MyApp.HomeScreen)
    end
    ```
    
    This validates at compile time that the modules are valid Dala.Screen modules.

## 18. **Incremental rendering with diff engine.**
    Dala now supports patch-based UI updates instead of full tree re-renders.
    
    **Architecture:**
    - UI trees use `Dala.Node` struct with stable `:id` field for identity
    - `Dala.Diff.diff(old, new)` compares two `Dala.Node` trees and produces patches
    - `Dala.Renderer.render_patches/5` sends only the patches to native (when supported)
    - `Dala.Screen` stores the previous tree (as `Dala.Node`) in `__dala__.last_tree`
    
    **Patch types:**
    - `{:replace, id, node}` — Replace entire node
    - `{:update_props, id, props}` — Update props on existing node
    - `{:insert, parent_id, index, node}` — Insert new node
    - `{:remove, id}` — Remove node
    
    **Node identity:**
    - `Dala.Node` requires `:id` field for proper reconciliation
    - `Dala.Node.from_map/2` converts maps to structs, generating IDs if needed
    - Explicit IDs are recommended for dynamic lists
    
    **Fallback:** If native doesn't support `apply_patches/1`, falls back to full render.
    
    **Testing:** `Dala.Diff` has comprehensive tests in `test/dala/diff_test.exs`.

## 20. **Bluetooth and WiFi support.**
    Dala provides full BLE and WiFi APIs via `Dala.Hardware.Bluetooth` and `Dala.Connectivity.Wifi`.
    
    **One-command setup:**
    ```bash
    mix dala.setup_bluetooth_wifi              # set up both platforms
    mix dala.setup_bluetooth_wifi --platform ios   # iOS only
    mix dala.setup_bluetooth_wifi --check          # verify without changes
    mix dala.bt_setup                              # shorter alias
    ```
    
    **Runtime API:**
    ```elixir
    Dala.Hardware.Bluetooth.state()                        # :powered_on | :powered_off | ...
    Dala.Hardware.Bluetooth.start_scan(socket)              # scan for BLE devices
    Dala.Hardware.Bluetooth.connect(socket, device_id)      # connect to device
    Dala.Hardware.Bluetooth.read_characteristic(socket, ...)  # GATT read
    Dala.Connectivity.Wifi.current_network()                # %{connected: true, ssid: ...}
    Dala.Connectivity.Wifi.connected?()                     # true | false
    Dala.Setup.diagnostic()                                 # full BT+WiFi diagnostic
    Dala.Setup.print_diagnostic()                           # print report to console
    ```
    
    **Events arrive as handle_info:**
    ```elixir
    handle_info({:bluetooth, :device_found, %{id: id, name: name, rssi: rssi}}, socket)
    handle_info({:bluetooth, :device_connected, %{id: id}}, socket)
    handle_info({:wifi, :state_changed, %{connected: bool, ssid: ssid}}, socket)
    ```
    
    **iOS:** CoreBluetooth via `DalaBluetoothManager` (ObjC) → C interface → Rust NIF.
    **Android:** `DalaBridge.java` → JNI → Rust NIF.
    
    **Permissions:** Request via `Dala.Permissions.request(socket, :bluetooth)` / `:wifi`.
    
    **Setup modules:** `Dala.Setup.Ios`, `Dala.Setup.Android` for programmatic setup.
    **Setup scripts:** `scripts/ios_setup.sh`, `scripts/android_setup.sh`.
    **Full docs:** `docs/bluetooth_wifi_implementation.md`.

## 21. **Plugin lifecycle and capability registration.**
    Plugins now follow a full lifecycle with capability-based registration.

    **Lifecycle states:** `:registered` → `:initialized` → `:active` → `:registered` → `:unloaded`

    **Behaviour callbacks** (`@behaviour Dala.Plugin`):
    - `init/1` (required) — resource allocation, returns `{:ok, state}` | `{:error, reason}`
    - `components/0` (required) — declare components
    - `capabilities/0` (required) — declare what the plugin provides
    - `permissions/0` — declare required permissions
    - `native_modules/1` — platform-specific native modules
    - `dependencies/0` — dependency ordering `[{plugin_name, version_req}]`
    - `validate_config/1` — compile-time config validation
    - `handle_event/3` — runtime event hooks
    - `cleanup/1` — resource deallocation / hot reload

    **Two DSL styles:**
    ```elixir
    # Style 1: Top-level declarations
    defmodule MyPlugin do
      use Dala.Plugin
      import Dala.Plugin

      description "My plugin"
      permission :camera
      dependency {:maps, "~> 1.0"}
      platform :ios
      native_module :ios, MyPlugin.IOS

      component "video" do
        prop "source", :string
        capability :gestures
      end
    end

    # Style 2: plugin do block
    defmodule MyPlugin do
      use Dala.Plugin

      plugin do
        plugin_description "My plugin"
        component :chart, MyPlugin.ChartComponent
        plugin_native :ios, MyPlugin.IOS
        plugin_permission :camera
        plugin_dependency {:maps, "~> 1.0"}
        plugin_platform :ios
      end
    end
    ```

    **Lifecycle management** (`Dala.Plugin.Lifecycle`):
    - `init/2` — calls `plugin.init/1`, transitions `:registered` → `:initialized`
    - `activate/1` — checks dependencies, transitions `:initialized` → `:active`
    - `deactivate/1` — transitions `:active` → `:registered`
    - `cleanup/1` — calls `plugin.cleanup/1`, transitions to `:unloaded`
    - `check_dependencies/1` — validates deps are registered and version-compatible
    - `negotiate_capabilities/2` — `{:ok, available}` | `{:error, {:missing, caps}}`
    - `supports_platform?/2` — checks platform metadata

    **Registry enhancements** (`Dala.Plugin.Registry`):
    - `get_status/1`, `set_status/2` — plugin status tracking
    - `get_state/1`, `set_state/2` — runtime state tracking
    - `resolve_dependency_order/0` — topological sort, detects cycles
    - `init_all/0` — initializes all plugins in dependency order
    - `cleanup_all/0` — cleans up in reverse dependency order
    - `find_by_capability/1`, `find_by_platform/1` — discovery queries

    **Key files:** `lib/dala/plugin.ex`, `lib/dala/plugin/lifecycle.ex`, `lib/dala/plugin/registry.ex`,
        `lib/dala/plugin/component.ex`, `lib/dala/plugin/component_dsl.ex`, `lib/dala/plugin/manifest.ex`, `lib/dala/plugin/protocol.ex`

## Where to look

| Question | File |
|---|---|
| Round-trip workflow + MCP setup | `guides/agentic_coding.md` |
| System architecture / native cocoon model | `CLAUDE.md` (top half), `ARCHITECTURE.md` |
| "I hit error X — has this happened before?" | `common_fixes.md` |
| "Does this user-facing setup issue ring a bell?" | `user_issues.md` |
| Open known issues with diagnoses + fixes | `issues.md` |
| Speculative ideas, longer-term plans | `future_developments.md`, `wire_tap.md`, `PLAN.md` |
| Per-feature deep dives (events, navigation, theming, ...) | `guides/*.md` |
| Render engine deep dive (Elixir → native data transfer) | `guides/render_engine.md` |
| UI design patterns (sigil vs DSL style) | `guides/ui_design.md` |
| Preview designer (drag-and-drop, code gen) | `dev_tools/INTERACTIVE_PREVIEW.md`, `dev_tools/dala/preview/` |
| Architecture decisions (one ADR per cross-cutting decision) | `docs/decisions/` |
| iOS device deployment (provisioning, build chain, gotchas) | `guides/ios_physical_device.md` |
| iOS ML support (Nx, Axon, EMLX, CoreML, ONNX) | `guides/ios_ml_support.md`, `lib/dala/ml/`, `dala/ML_INTEGRATION_SUMMARY.md` |
| Bluetooth/WiFi setup and API | `docs/bluetooth_wifi_implementation.md`, `lib/dala/hardware/bluetooth.ex`, `lib/dala/connectivity/wifi.ex` |
| Bluetooth/WiFi setup scripts | `scripts/ios_setup.sh`, `scripts/android_setup.sh` |
| iOS Bluetooth native code | `ios/DalaBluetoothManager.{h,m}`, `ios/DalaBluetoothCInterface.m` |
| iOS Motion native code | `ios/DalaMotionManager.{h,m}`, `ios/DalaMotionCInterface.m` |
| iOS NFC native code | `ios/DalaNFCManager.{h,m}`, `ios/DalaNFCCInterface.m` |
| Android Bluetooth/WiFi/Motion/NFC bridge | `android/src/main/java/com/example/dala/DalaBridge.java` |
| Generator templates (dala_new) | `dala_new/priv/templates/dala.new/` |
| Build / release tooling | `dala_dev/scripts/release/`, `dala_dev/build_release.md` |
| Plugin lifecycle, capabilities, registry | `lib/dala/plugin.ex`, `lib/dala/plugin/lifecycle.ex`, `lib/dala/plugin/registry.ex` |
| Event system (unified API, bridge, target, throttle) | `lib/dala/event/event.ex`, `lib/dala/event/bridge.ex`, `lib/dala/event/target.ex`, `lib/dala/event/throttle.ex` |
| NativeView component lifecycle | `lib/dala/ui/native_view.ex`, `lib/dala/ui/native_view/server.ex`, `lib/dala/ui/native_view/registry.ex` |
| Background execution, Linking, Settings, State | `lib/dala/platform/background.ex`, `lib/dala/platform/linking.ex`, `lib/dala/platform/settings.ex`, `lib/dala/platform/state.ex` |
| Storage (files, blobs, photos) | `guides/storage.md`, `lib/dala/storage/storage.ex`, `lib/dala/storage/blob.ex`, `lib/dala/storage/files.ex`, `lib/dala/media/photos.ex` |
| Alerts, toasts, WebView bridge, Motion sensors | `lib/dala/ui/feedback/alert.ex`, `lib/dala/ui/embedded/webview.ex`, `lib/dala/ui/sensor/motion.ex` |
| NFC tag reading | `lib/dala/hardware/nfc.ex` |
| NFC / barcode format parser | `lib/dala/ui/scan.ex` |
| Wakelock, List rendering, PubSub | `lib/dala/hardware/wakelock.ex`, `lib/dala/list.ex`, `lib/dala/pubsub.ex` |
| Distribution, Permissions | `lib/dala/connectivity/dist.ex`, `lib/dala/permissions.ex` |
| **Media Runtime** (video, scene graph, clock, filters, subtitles, adaptive bitrate, GPU surface) | `guides/media_runtime.md`, `lib/dala/media/`, `lib/dala/gpu.ex`, `lib/dala/gpu/command.ex`, `native/dala_gpu/` |
| **GPU Compute** (EXCubeCL, CubeCL kernels, buffer management, pipelines, ML inference, media processing) | `guides/gpu_compute.md`, `lib/dala/gpu/compute/`, `lib/dala/ml/gpu/`, `lib/dala/media/gpu/` |
| **ExBurn (Burn)** (Nx backend, training loop, serving, GPU bridge) | `lib/dala/ml/burn.ex`, `lib/dala/ml/burn/`, `lib/dala/ml/burn.ex` (NifHelper, Application, Serving.Server) |

## iOS ML Support (Nx ecosystem + CoreML + ONNX)

Dala supports machine learning via three paths:

### Nx Ecosystem (Pure Elixir, Cross-Platform)

- **Nx**: Pure Elixir, works on any platform ✅
- **Scholar**: Traditional ML (regression, clustering, SVM, etc.), pure Elixir ✅
- **NxSignal**: DSP (digital signal processing) for audio/time series, pure Elixir ✅
- **Axon**: Neural networks, pure Elixir ✅
- **EMLX**: MLX backend for Apple Silicon — **recommended for iOS** ✅

### CoreML (iOS-Native, Hardware-Accelerated)

- **CoreML**: Apple's native ML framework — **best performance on iOS** 🚀
  - Uses Apple Neural Engine (ANE) for hardware acceleration
  - Supports .mlmodel and .mlpackage formats
  - Synchronous predictions via NIF (Mutex-captured ObjC callback)
  - Runs on dirty CPU scheduler
  - Access via `Dala.ML.CoreML` module

### ONNX Runtime (Cross-Platform, Placeholder)

- **ONNX Runtime**: Industry-standard ONNX inference engine
  - **iOS**: Uses CoreML EP (Execution Provider) for Neural Engine
  - **Android**: Uses NNAPI EP for hardware acceleration
  - **Desktop**: Uses CPU/CUDA/TensorRT EPs
  - Access via `Dala.ML.ONNX` module
  - Rust core: `native/dala_onnx/` (C ABI)
  - **Status**: Placeholder — thread-safe structure ready, actual inference not yet linked

### ExBurn / Burn (Cross-Platform, GPU-Accelerated)

- **ExBurn**: Bridge between Nx and the Burn deep learning framework (Rust)
  - `Nx.Backend` implementation delegating to Burn via Rust NIFs
  - GPU acceleration via Burn's CubeCL backend (Metal/Vulkan/CUDA)
  - Training loop with Adam/SGD/RMSprop, LR scheduling, gradient clipping, callbacks
  - Nx.Serving integration for batched concurrent inference
  - Model management: compile, save/load, serialize, summary, quantize, benchmark, clone
  - Layer freeze/unfreeze for fine-tuning workflows
  - Glorot/Xavier weight initialization
  - Autodiff gradients via Burn Autodiff<CubeCL> (exact, not numerical)
  - Profile step for timing forward/backward/optimizer phases
  - Gradient accumulation for effective larger batch sizes
  - Nesterov momentum for SGD optimizer
  - Accuracy tracking during training
  - Model export/import (Erlang terms + JSON formats)
  - `ExBurn.NifHelper` — safe NIF wrappers with `{:ok, result}` tuples
  - `ExBurn.Serving.Server` — `Nx.Serving` behaviour for batched concurrent inference
  - `ExBurn.Application` — OTP application callback for NIF loading
  - Access via `Dala.ML.Burn`, `Dala.ML.Burn.Training`, `Dala.ML.Burn.Serving`
  - **Status**: v0.5.0 — Full Nx backend, defn compiler, training loop, serving, model management, NifHelper, Application. Uses Burn 0.21 with real Autodiff<CubeCL> gradients (not numerical).

**Not supported on iOS:** Emily (macOS-only), NxIREE, EXLA/XLA, Torchx.

**Newly integrated (v0.0.6+):**
- Scholar, NxSignal, Axon are now direct dependencies
- CoreML bridge for iOS-native inference (synchronous, dirty CPU scheduled)
- ONNX Runtime for cross-platform production inference (placeholder)
- `Dala.ML.setup/0` unified zero-config entry point
- `Dala.ML.predict/2` unified predict dispatching to CoreML/ONNX/Axon
- `Dala.ML.benchmark/1` for backend performance measurement
- ExBurn (Burn) bridge for GPU-accelerated ML via `Dala.ML.Burn`

Use `Dala.ML.setup/0` for zero-config setup (replaces `Dala.ML.EMLX.setup/0`).

Key constraints:
1. **No JIT on iOS devices** — W^X policy blocks JIT. `Dala.ML.setup/0` handles this automatically.
2. **Metal GPU available** — EMLX uses MLX with Metal on iOS devices and simulator.
3. **Unified memory** — Apple Silicon's shared CPU/GPU memory makes EMLX efficient.
4. **CoreML is synchronous** — NIF captures ObjC callback result via Mutex, returns `{:ok, result}` or `{:error, reason}`.
5. **ONNX NIFs are dirty CPU scheduled** — won't block BEAM schedulers.
6. **ONNX available on iOS + Android** — NIFs gated with `#[cfg(any(target_os = "ios", target_os = "android"))]`.

Helper modules: `Dala.ML`, `Dala.ML.EMLX`, `Dala.Ml.Nx`, `Dala.ML.CoreML`, `Dala.ML.ONNX` in `lib/dala/ml/`.
Full guide: `guides/ios_ml_support.md`
Summary: `dala/ML_INTEGRATION_SUMMARY.md`

## 22. **Dev-only UI preview and design tool.**
    `Dala.Designer` module (in `dev_tools/` directory) provides two modes:

    1. **Static preview** — generates standalone HTML with CSS that mimics Dala's styling.
    2. **Live designer** — Phoenix LiveView server with drag-and-drop component palette,
       property editor, live phone-frame preview, and code generation (sigil or DSL style).

    **Key points:**
    - Lives in `dev_tools/` directory — only compiled in `:dev` environment
    - Not included in Hex package (excluded via `mix.exs` package/0 filter)
    - Static preview works without any server
    - Live designer starts a Phoenix endpoint with LiveView
    - Code generation supports Spark DSL style

    **Static preview:**
    ```elixir
    Dala.Designer.preview(MyApp.HomeScreen)
    Dala.Designer.preview_to_file(MyApp.HomeScreen, "preview.html")
    Dala.Designer.preview_and_open(MyApp.HomeScreen)
    ```

    **Live designer:**
    ```elixir
    Dala.Designer.start_designer(port: 4200)
    Dala.Designer.generate_code(tree, "MyApp.HomeScreen")
    ```

    ```bash
    # Static preview
    mix dala.designer MyApp.HomeScreen
    mix dala.designer MyApp.HomeScreen --output custom.html --no-open

    # Live designer
    mix dala.designer --live
    mix dala.designer --live --port 4200 --module MyApp.HomeScreen
    ```

    **Implementation:**
    - `dev_tools/dala/preview.ex` — Main module: static preview + `start_designer/1` + `generate_code/3`
    - `dev_tools/dala/preview/codegen.ex` — Code generation: sigil + DSL styles, handler extraction
    - `dev_tools/dala/preview/canvas.ex` — LiveView: drag-and-drop designer with property editor
    - `dev_tools/dala/preview/live.ex` — Phoenix endpoint setup and server lifecycle
    - `dev_tools/dala/preview/live/layout.ex` — Root HTML layout with LiveView client JS
    - `dev_tools/dala/preview/example.ex` — Example UI trees
    - `dev_tools/mix/tasks/dala/preview.ex` — Mix task with `--live` flag

    **Code generation:**
    - `Dala.Designer.Codegen.generate_dsl/3` — Spark DSL style with snake_case entities
    - `Dala.Designer.Codegen.extract_handlers/1` — Extract event handler atoms from UI tree
    - Auto-generates `handle_event/3` stubs for all event handlers found in the tree

## 24. **GPU compute via EXCubeCL (v0.7.0).**
    Dala integrates EXCubeCL for GPU compute workloads (image processing, AI inference, realtime effects).
    
    **Key modules:**
    - `Dala.Gpu.Compute` — High-level API: buffers, kernels, pipelines, Nx bridge
    - `Dala.Gpu.Compute.Buffer` — Typed buffer struct wrapper
    - `Dala.Gpu.Compute.Kernel` — Kernel execution + custom kernel registry
    - `Dala.Gpu.Compute.Pipeline` — Multi-stage GPU pipelines (delegates to `ExCubecl.pipeline/0`)
    - `ExCubecl.Command` — Typed struct for pipeline commands
    - `Dala.Gpu.Compute.device_count/0` — Number of available GPU devices
    - `Dala.Gpu.Compute.kernels/0` — List of available kernel names
    - `Dala.Gpu.Compute.supported_dtypes/0` — List of supported dtype atoms
    - `Dala.Gpu.Compute.available?/0` — Check if NIF is loaded and functional
    - `Dala.ML.Gpu.Inference` — GPU-accelerated ML inference with VideoFrame support
    - `Dala.Media.Gpu.Processor` — GPU-accelerated video/image processing
    
    **EXCubeCL 0.7.0 Media Modules (via `Dala.Media.Gpu.Processor`):**
    - `ExCubecl.Media` — Media I/O: open, streams, read_frame, close
    - `ExCubecl.Video` — Video ops: overlay, mix, scale, crop, convert
    - `ExCubecl.Audio` — Audio ops: mix, overlay, resample, channel conversion
    - `ExCubecl.Filter` — GPU filters: apply, chain (gaussian_blur, sharpen, denoise, etc.)
    - `ExCubecl.Transcode` — Encoding/muxing: start, write_frame, write_samples, finish
    - `ExCubecl.VideoFrame` / `ExCubecl.AudioSamples` — GPU-resident media types
    - `ExCubecl.MediaPipeline` — GenServer behaviour for real-time media pipelines
    
    **Key patterns:**
    - GPU compute is dirty-CPU scheduled (won't block BEAM)
    - On iOS → Metal shaders, Android → OpenGL ES compute, Desktop → CPU fallback
    - Use `Dala.Gpu.Compute.device_info()` to check GPU availability
    - Buffers are auto-freed via Rust ResourceArc (no manual free needed)
    - For rendering results to screen, use `run_to_surface/5` to avoid CPU read-back
    - Pipelines batch multiple kernels into a single submission
    - EXCubeCL uses string kernel names (`"elementwise_add"`), Dala translates atoms at the boundary
    - EXCubeCL `read/1` returns `{:ok, binary()}` — already unwrapped by `Dala.Gpu.Compute.read/1`
    - EXCubeCL uses `Jason.encode!/1` for kernel parameter JSON encoding
    - All EXCubeCL functions return `{:ok, result}` tuples
    - Supports `:u8` (8-bit unsigned integer) dtype
    - 24 CPU-side kernels implemented: elementwise ops, activations, video/audio filters
    
    **Integration points:**
    - `Dala.Gpu` delegates to `Dala.Gpu.Compute` via `compute_buffer/3`, `compute_run/4`, etc.
    - `Dala.ML` includes `:gpu_compute` in `available_backends/0`
    - `Dala.ML.setup/0` does NOT auto-configure GPU compute (opt-in)
    
    **Full guide:** `guides/gpu_compute.md`

## 23. **Event system and additional platform APIs.**
    Dala provides a unified event system and several additional platform APIs:
    
    - `Dala.Event` — Unified event emission: `dispatch/4`, `emit/4`, `send_test/6`
    - `Dala.Event.Bridge` — Event routing between native and BEAM
    - `Dala.Event.Throttle` — Event throttling/debouncing
    - `Dala.Event.Trace` — Event tracing for debugging
    - `Dala.Ui.NativeView` — Stateful Elixir processes paired with platform-native views
    - `Dala.Platform.Background` — Background execution keep-alive
    - `Dala.Platform.Linking` — Open URLs, deep links
    - `Dala.Platform.Settings` — Persistent settings (UserDefaults/SharedPreferences)
    - `Dala.Platform.State` — DETS-backed persistent key-value store
    - `Dala.Storage.Blob` — Binary data via native blob references
    - `Dala.Storage.Storage` — App-local file storage with named locations
    - `Dala.Wakelock` — Screen wakelock
    - `Dala.Ui.Feedback.Alert` — Native alerts, action sheets, toasts
    - `Dala.Ui.Embedded.Webview` — Bidirectional JS bridge for WebView (includes `interact/2`)
    - `Dala.Ui.Sensor.Motion` — Accelerometer and gyroscope
    - `Dala.List` — List rendering with custom item renderers
    - `Dala.PubSub` — Local PubSub via Elixir Registry
    - `Dala.Connectivity.Dist` — Platform-aware Erlang distribution startup

## Conventions worth knowing

- **Terse responses.** Default to short, dense communication. The user reads code
  changes via diff; don't recap them in chat.
- **No premature abstractions.** Three similar lines beats a half-baked helper.
- **No comments explaining the code.** Comments explain *why* — invariants,
  hidden constraints, surprising behavior. Never the *what*.
- **Trust internal callers.** Don't add validation/error handling for cases
  that can't happen. Validate at system boundaries (user input, external APIs).
- **Don't add features beyond what was requested.** A bug fix doesn't need
  surrounding cleanup; a one-shot doesn't need a helper.

## Hex package contents

The `package` function in `mix.exs` defines what goes into the Hex tarball.
Currently: `lib/ native/ priv/ android/ ios/ assets/ mix.exs mix.lock README.md LICENSE`.

### What's included

| Directory | Purpose |
|-----------|--------|
| `lib/` | Elixir source code |
| `native/dala_nif/` | Rust NIF source (built by Rustler during `mix compile`) |
| `native/dala_beam/` | Rust BEAM integration source (EPMD, driver tabs) |
| `android/jni/` | Android NDK C bridge + Rust source for BEAM |
| `ios/` | iOS native files (.m, .h, .swift) + Rust source for BEAM |
| `priv/tags/` | Platform tags for `Dala.Native` |
| `assets/` | Logo and visual assets |

### What's explicitly excluded (via `.gitignore` + disk cleanup)

| Pattern | Why |
|---------|----|
| `**/target/` | Rust build artifacts (58MB+ in `android/jni/rust/target/`) |
| `priv/native/*.so`, `*.dylib` | Pre-compiled NIFs — built during `mix compile` |

### Key gotcha

`mix hex.build` packages **files on disk**, not just git-tracked files.
Even `git rm --cached` won't help if the files still exist on disk —
they'll be included in the tarball. Always delete build artifacts from
 disk before building:

```bash
rm -rf android/jni/rust/target/ ios/rust/target/
rm -f priv/native/*.so
```

The `.gitignore` patterns prevent accidental re-commit, but the immediate
build is about what's on disk.

### Package size check

```bash
mix hex.build 2>&1 | tail -5  # should be under 16MB compressed
ls -lh dala-*.tar              # typical size: ~385KB
```

---

## Keep this file up to date

The next agent's first decision will be informed by this file. Stale guidance
here causes wrong decisions everywhere downstream.

When you change something this doc describes — repo topology, conventions,
gotchas, a new piece of CLI surface area, a deprecated workflow — **update
this file in the same commit**. Not in a follow-up. The history of "I'll fix
the docs later" is that it doesn't happen.

If you discover a gotcha that bit you — something that should have been on the
pre-empt list but wasn't — add it to rule #N+1 with a one-line summary and a
link to the commit/test that demonstrates it. Future you will thank present
you.
