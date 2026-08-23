# Changelog

All notable changes to Dala are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/).

## [0.10.0]

### Added

- **Spark DSL `for` comprehensions** — `for item <- @items do ... end` renders
  at expansion time; optional keyed form `for item <- @items, id: item.id do`
  gives rows stable ids (`<parent>:item-<key>`) so the diff engine patches
  individual rows.
- **`defui` local components** — reusable UI fragments inside a screen module
  with positional parameters; call sites splice returned nodes as siblings.
  Compile-time arity/block validation; defui params cannot cross loop bounds.
- **Compile-time ref checking** — undeclared `@ref`s emit compiler warnings
  (they previously rendered empty silently).
- **Strict prop validation** — unknown props on any component now fail the
  build with did-you-mean suggestions instead of being dropped by `struct/2`.
- **Prop-call style rejected** — `column do gap :space_sm end` fails with a
  hint pointing at keyword args.
- **Unknown components fail verification** — parsed as `:unknown_component`
  markers and reported as compile errors instead of silently dropping the
  subtree.
- **`unless` branch swap** — desugars to a conditional's ELSE branch (no
  negation AST); conditions validated at parse time (refs, literals,
  compute fns only).
- **Screen-name inference** — omit `name:` to derive it from the module name
  (`MyApp.CounterScreen` → `:counter`).
- **Handler diagnostics** — missing/unused `handle_event` clauses reported via
  `@after_verify` on every `mix compile`; clause heads read from beam debug_info.
- **`mix dala.verify --components --markdown-output <path>`** — generates a
  component reference doc from the registry.
- **`Dala.Renderer` facade additions** — `encode_set_text/2`,
  `encode_register_string/2`, `encode_event/4`, `encode_patch_node/3`,
  `compute_layout_hash/1`.
- **`Dala.Diff.compute_field_mask/2`** facade over `Dala.Ui.Diff`.
- **`Dala.Ui.Widgets.variant_presets/0`** — single source of truth for text
  variants, shared with compile-time verification.
- **Plugin component support in NativeView** — plugin components
  (`{:plugin_component, type}`) skip BEAM-side mount/update/event callbacks;
  native side owns rendering.
- **CI workflow** (`.github/workflows/elixir.yml`) — format / credo / test
  matrix + dialyzer job.
- **Dialyzer** config (`priv/plts`, ignore-warnings file).

### Changed

- **ML/GPU deps are now optional** (`nx`, `emlx`, `polaris`, `scholar`,
  `nx_signal`, `axon`, `ex_cubecl` ~> 0.8, `ex_burn` ~> 0.6). Core runtime
  works without them; all calls are runtime-guarded via
  `Code.ensure_loaded?`. Apps using ML add these to their own mix.exs.
  - `Dala.ML.setup/0` returns `{:error, :nx_not_available}` when Nx is absent;
    new `Dala.ML.nx_available?/0`.
  - `Dala.ML.benchmark/1` uses deterministic matrices (no Nx.Random), isolates
    the Burn benchmark in a supervised process with a 10s timeout.
- **`Dala.Ui.List.expand/4`** — accepts a list of root nodes and screen
  assigns; expands DSL `conditional` and `for` nodes at render time.
- **`Dala.Screen.do_render/3`** — passes assigns into list expansion; patch
  rendering routed through the `Dala.Renderer` facade.
- **WebVTT parser** accepts an optional cue identifier line before timings.
- **SRT parsing** no longer crashes on malformed cues (error tuples propagate).
- Version bump 0.8.1 → 0.9.0.
- Docs: `guides/spark_dsl.md` and `skill-generate-screen-dsl.md` rewritten for
  the new DSL surface; example apps migrated to flat sections + `for`/`defui`.

### Fixed

- `Dala.Setup` pointed at removed modules (`Dala.Bluetooth`,
  `Dala.WiFi`) → now `Dala.Hardware.Bluetooth` / `Dala.Connectivity.Wifi`.
- Verifier line extraction handled Spark anno metadata variants incorrectly.
- Multi-word component types mangled by `String.downcase/1` in verifier →
  `Macro.underscore/1`.
- Unset (`nil`) event-handler props no longer flagged as phantom handlers.

### Known issues

Found in review of this changeset — fix before release:

- **`for` bodies reject documented features** (`render.ex` evaluates children
  at compile time with empty assigns): `@ref` and `compute(fn)` inside a `for`
  fail compilation with a cryptic "undefined variable assigns"; nested `for`
  crashes with "cannot escape #Function".
- **Duplicate node ids within rows**: all siblings at each depth share one id
  (`row_id` / `"#{row_id}:c"`), clobbering explicit ids and producing colliding
  `update_props` patches from `Dala.Diff`.
- **Handler collection misses conditional branches and tuple events** — false
  "never referenced" warnings; handlers referenced only inside `if/unless` or
  via `{tag, arg}` tuples are invisible to missing-handler checks too.
- **Spark extension verify callback rejects tuple event values**
  (`dsl.ex verify_entity`) — every compile of screens using `{tag, arg}`
  events prints "Exception while verifying".
- `examples/demo_app` cannot compile: path dep pulls in `dev_tools/` which
  needs `phoenix_live_view`.
- CI: workflow triggers on `main` but default branch is `master`; dialyxir
  invoked with invalid `--plt <path>` usage.
- `NOTICE` deleted — removes MIT attribution for original Mob code.

## [0.8.1]

Maintenance release (see git history).

## [0.8.0]

- New components: `:skeleton`, `:empty_state`, `:avatar`, `:stepper`, `:grid`.
- Accessibility props on all components (`accessibility_label/hint/role/value/hidden`).
- Theme API additions (`Dala.Theme.resolve/1`, `set_accent/1`,
  `prefers_reduced_motion/0`, custom adaptive themes, line-height tokens).
- Expanded icon set (28 → 104 logical names).
- DSL verification (`Dala.Spark.DslVerifier`, `mix dala.verify`).
- Incremental rendering via diff engine (`Dala.Diff`, patch-based updates).
- Bluetooth/WiFi APIs (`Dala.Hardware.Bluetooth`, `Dala.Connectivity.Wifi`).
- Plugin lifecycle with capability registration.
- GPU compute via EXCubeCL integration.
- Dev-only UI preview/designer tool (`Dala.Designer`).

## [0.7.x]

- Media runtime (video, scene graph, clock, filters, subtitles, adaptive
  bitrate, GPU surface).
- ExBurn (Burn) bridge: Nx backend, training loop, serving, model management.
- ML stack unification (`Dala.ML.setup/0`, CoreML bridge, ONNX placeholder).

## [0.6.x]

- Event system (`Dala.Event.*`), platform APIs (background, linking, settings,
  state), storage/blob/files, WebView interact API, motion sensors, NFC.

[Unreleased]: https://github.com/manhvu/dala/compare/v0.8.1...HEAD
