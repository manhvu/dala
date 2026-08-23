defmodule DemoApp.HomeScreen do
  @moduledoc """
  Home screen with complex layout demonstrating various UI components.
  """
  use Dala.Spark.Dsl

  attributes do
    attribute(:count, :integer, default: 0)
    attribute(:show_detail, :boolean, default: false)
  end

  screen name: :home do
    column padding: 16, gap: 12 do
      # Header section
      box padding: 20, background: "#f0f0f0", corner_radius: 12 do
        text("Welcome to Dala Demo", text_size: :xl, font_weight: "bold")
      end

      # Counter section
      row spacing: 12, alignment: :center do
        text("Count: @count", text_size: :lg)
        button("-", on_tap: :decrement)
        button("+", on_tap: :increment)
      end

      divider()

      # Navigation buttons
      text("Navigation Examples", text_size: :lg, font_weight: "bold")
      button("Push Detail Screen", on_tap: :push_detail)
      button("Show Modal", on_tap: :show_modal)
      button("Open Forms Screen", on_tap: :open_forms)

      spacer(size: 20)

      # Info text
      text("Use tab bar below to switch between screens", text_size: :sm, text_color: "#666")
    end
  end

  def handle_event(:increment, _params, socket) do
    new_count = socket.assigns.count + 1
    {:noreply, Dala.Socket.assign(socket, :count, new_count)}
  end

  def handle_event(:decrement, _params, socket) do
    new_count = max(0, socket.assigns.count - 1)
    {:noreply, Dala.Socket.assign(socket, :count, new_count)}
  end

  def handle_event(:push_detail, _params, socket) do
    {:noreply, Dala.Screen.push_screen(socket, DemoApp.DetailScreen)}
  end

  def handle_event(:show_modal, _params, socket) do
    {:noreply, Dala.Screen.present_modal(socket, DemoApp.ModalScreen)}
  end

  def handle_event(:open_forms, _params, socket) do
    {:noreply, Dala.Screen.push_screen(socket, DemoApp.FormsScreen)}
  end
end
