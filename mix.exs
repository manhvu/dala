defmodule Dala.MixProject do
  use Mix.Project

  def project do
    [
      app: :dala,
      version: "0.10.0",
      elixir: "~> 1.18",
      erlang: ">= 27.0",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description:
        "Dala is a native mobile framework for Elixir powered by the BEAM VM. Build iOS and Android apps with OTP, lightweight processes, fault tolerance, AI/ML.",
      source_url: "https://github.com/manhvu/dala",
      homepage_url: "https://hexdocs.pm/dala",
      package: package(),
      docs: docs(),
      # Rustler configuration
      rustler_crates: rustler_crates(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dala.plt"},
        # Optional ML deps may not be loaded; calls into them are runtime-guarded
        ignore_warnings: "dialyzer.ignore-warnings"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo/Dala_logo_512.png",
      source_url: "https://github.com/manhvu/dala",
      source_url_pattern: "https://github.com/manhvu/dala/blob/main/%{path}#L%{line}",
      extras: [
        "README.md": [title: "Dala"],
        "guides/getting_started.md": [title: "Getting Started"],
        "guides/architecture.md": [title: "Architecture & Prior Art"],
        "guides/build_and_beam_loading.md": [title: "Build & BEAM Loading"],
        "guides/screen_lifecycle.md": [title: "Screen Lifecycle"],
        "guides/components.md": [title: "Components"],
        "guides/styling.md": [title: "Styling & Native Rendering"],
        "guides/theming.md": [title: "Theming"],
        "guides/navigation.md": [title: "Navigation"],
        "guides/screen_manager_pubsub.md": [title: "Screen Manager"],
        "guides/device_capabilities.md": [title: "Device Capabilities"],
        "guides/data.md": [title: "Data & Persistence"],
        "guides/render_engine.md": [title: "Render Engine"],
        "guides/binary_protocol.md": [title: "Binary Protocol"],
        "guides/ui_design.md": [title: "UI Design"],
        "guides/ui_render_pipeline.md": [title: "UI Render Pipeline"],
        "guides/events.md": [title: "Events"],
        "guides/event_model.md": [title: "Event Model"],
        "guides/event_audit.md": [title: "Event Audit"],
        "guides/spark_dsl.md": [title: "Spark DSL"],
        "guides/media_runtime.md": [title: "Media Runtime"],
        "guides/gpu_render_pipeline.md": [title: "GPU Render Pipeline"],
        "guides/gpu_compute.md": [title: "GPU Compute"],
        "guides/testing.md": [title: "Testing"],
        "guides/liveview.md": [title: "LiveView Integration"],
        "guides/ios_ml_support.md": [title: "iOS ML Support"],
        "guides/ex_burn.md": [title: "ExBurn (Burn) Integration"],
        "guides/ios_physical_device.md": [title: "iOS Physical Device"],
        "guides/rustler_complete.md": [title: "Rustler in Mobile"],
        "guides/emlx_ios_summary.md": [title: "EMLX iOS Summary"],
        "guides/publishing.md": [title: "Publishing to App Store / TestFlight"],
        "guides/troubleshooting.md": [title: "Troubleshooting"],
        "guides/agentic_coding.md": [title: "Agentic Coding"],
        "guides/security.md": [title: "Security Guide"],
        "guides/plugin_architecture.md": [title: "Plugin"]
      ],
      groups_for_extras: [
        "Getting Started": ~r/guides\/(getting_started|architecture|build_and_beam_loading)\.md/,
        "UI & Components":
          ~r/guides\/(components|styling|theming|ui_|render_engine|binary_protocol|spark_dsl|screen_lifecycle|navigation|screen_manager_pubsub)\.md/,
        "Events & Interaction": ~r/guides\/(events|event_)\.md/,
        "Data & Device APIs": ~r/guides\/(data|device_capabilities)\.md/,
        "Media & GPU": ~r/guides\/(media_runtime|gpu_render_pipeline|gpu_compute)\.md/,
        "Testing & Development": ~r/guides\/(testing|agentic_coding)\.md/,
        "iOS & Rust": ~r/guides\/(ios_|rustler_|emlx_|ex_burn)\.md/,
        Plugins: ~r/guides\/plugin_\.md/,
        "Advanced Topics": ~r/guides\/(liveview|publishing|security|troubleshooting)\.md/
      ],
      groups_for_modules: [
        Core: [Dala, Dala.App, Dala.Screen, Dala.Socket, Dala.Platform.State],
        UI: [
          Dala.Ui.Widgets,
          Dala.Node,
          Dala.Diff,
          Dala.Ui.Diff,
          Dala.Renderer,
          Dala.Ui.Renderer,
          Dala.Ui.Style,
          Dala.Ui.List,
          Dala.Ui.NativeView,
          Dala.Ui.NativeView.Registry,
          Dala.Ui.NativeView.Server,
          Dala.Ui.Feedback.Alert,
          Dala.Ui.Sensor.Motion,
          Dala.Ui.Embedded.Webview,
          Dala.Theme,
          Dala.Theme.Obsidian,
          Dala.Theme.Citrus,
          Dala.Theme.Birch
        ],
        Navigation: [Dala.Nav.Registry],
        "Device APIs": [
          Dala.Hardware.Haptic,
          Dala.Platform.Clipboard,
          Dala.Platform.Share,
          Dala.Permissions,
          Dala.Hardware.Biometric,
          Dala.Platform.Location,
          Dala.Hardware.Scanner,
          Dala.Platform.Notify
        ],
        "Testing & Debugging": [Dala.Test],
        Plugins: [
          Dala.Plugin,
          Dala.Plugin.Component,
          Dala.Plugin.ComponentDSL,
          Dala.Plugin.Lifecycle,
          Dala.Plugin.Registry,
          Dala.Plugin.Protocol,
          Dala.Plugin.Manifest
        ],
        "GPU Compute": [
          Dala.Gpu.Compute,
          Dala.Gpu.Compute.Buffer,
          Dala.Gpu.Compute.Kernel,
          Dala.Gpu.Compute.Pipeline,
          Dala.ML.Gpu.Inference,
          Dala.Media.Gpu.Processor
        ],
        "ML & Burn": [
          Dala.ML,
          Dala.ML.Burn,
          Dala.ML.Burn.Training,
          Dala.ML.Burn.Serving
        ],
        Internals: [Dala.Dist, Dala.NativeLogger, Dala.List]
      ],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script>
      // Ensure code blocks with language hints are highlighted
      document.querySelectorAll("pre code").forEach(el => {
        if (!el.className) el.className = "language-elixir";
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""

  # Rustler crate configuration
  defp rustler_crates do
    [
      dala_nif: [
        path: "native/dala_nif",
        mode: if(Mix.env() == :prod, do: :release, else: :debug)
      ]
    ]
  end

  defp elixirc_paths(:test),
    do: [
      "lib",
      "test/support",
      "test/onboarding",
      "test/onboarding/support",
      "dev_tools",
      "dev_tools/dala/preview",
      "dev_tools/test"
    ]

  defp elixirc_paths(:dev), do: ["lib", "dev_tools", "dev_tools/dala/preview", "dev_tools/test"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT", "MPL-2.0"],
      links: %{"GitHub" => "https://github.com/manhvu/dala"},
      files: ~w(
        lib native priv
        android ios assets
        mix.exs mix.lock
        README.md LICENSE
      )
    ]
  end

  defp deps do
    [
      {:nimble_parsec, "~> 1.4"},
      {:spark, "~> 2.7"},
      {:rustler, "~> 0.37", runtime: false},

      # Dev deps.
      {:phoenix_live_view, "~> 1.1", only: [:dev, :test]},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.2", only: [:dev, :test], runtime: false},

      # JSON encoding (used by plugins, media, webview bridge)
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # ML dependencies — optional. Core UI/runtime works without them.
      # Apps that use Dala.ML / Dala.Gpu.Compute should add these to their
      # own mix.exs. All calls into these libraries are runtime-guarded.
      {:nx, "~> 0.12", optional: true},
      {:emlx, "~> 0.3", optional: true},
      {:polaris, "~> 0.1", optional: true},
      {:scholar, "~> 0.4", optional: true},
      {:nx_signal, "~> 0.3", optional: true},
      {:axon, "~> 0.8", optional: true},

      # GPU compute runtime (CubeCL via Rust NIFs) — optional
      {:ex_cubecl, "~> 0.8", optional: true},

      # Burn deep learning framework (Nx backend via Rust NIF) — optional
      {:ex_burn, "~> 0.6", optional: true}
    ]
  end
end
