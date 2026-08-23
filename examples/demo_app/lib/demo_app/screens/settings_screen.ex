defmodule DemoApp.SettingsScreen do
  @moduledoc """
  Settings screen demonstrating switches, toggles, and layout options.
  """
  use Dala.Spark.Dsl

  attributes do
    attribute(:dark_mode, :boolean, default: false)
    attribute(:auto_update, :boolean, default: true)
    attribute(:analytics, :boolean, default: false)
    attribute(:cache_size, :string, default: "125 MB")
  end

  defui setting_row(label, value, event) do
    row spacing: 12, alignment: :center do
      text(label)
      switch(value: value, on_toggle: event)
    end
  end

  screen name: :settings do
    scroll padding: 16 do
      text("Settings", text_size: :xl, font_weight: "bold")
      text("Configure your app preferences", text_size: :sm, text_color: "#666")
      divider()

      # General section
      text("General", font_weight: "bold", text_size: :lg)
      setting_row("Dark Mode", @dark_mode, :toggle_dark_mode)
      setting_row("Auto Update", @auto_update, :toggle_auto_update)
      divider()

      # Privacy section
      text("Privacy", font_weight: "bold", text_size: :lg)
      setting_row("Analytics", @analytics, :toggle_analytics)
      divider()

      # Storage section
      text("Storage", font_weight: "bold", text_size: :lg)

      row spacing: 12, alignment: :center do
        text("Cache Size")
        text(@cache_size, text_color: "#666")
      end

      button("Clear Cache", on_tap: :clear_cache, variant: :outlined)

      spacer(size: 40)

      # About section
      box padding: 16, background: "#f9f9f9", corner_radius: 8 do
        column gap: 4 do
          text("Dala Demo App v0.1.0", text_size: :sm, text_color: "#666")
          text("Built with Dala framework", text_size: :sm, text_color: "#666")
        end
      end
    end
  end

  def handle_event(:toggle_dark_mode, %{"value" => value}, socket) do
    {:noreply, Dala.Socket.assign(socket, :dark_mode, value)}
  end

  def handle_event(:toggle_auto_update, %{"value" => value}, socket) do
    {:noreply, Dala.Socket.assign(socket, :auto_update, value)}
  end

  def handle_event(:toggle_analytics, %{"value" => value}, socket) do
    {:noreply, Dala.Socket.assign(socket, :analytics, value)}
  end

  def handle_event(:clear_cache, _params, socket) do
    {:noreply, Dala.Socket.assign(socket, :cache_size, "0 MB")}
  end
end
