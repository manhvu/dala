defmodule DemoApp.DetailScreen do
  @moduledoc """
  Detail screen demonstrating navigation stack with back button.
  """
  use Dala.Spark.Dsl

  attributes do
    attribute(:items, :list, default: ["Item A", "Item B", "Item C"])
    attribute(:selected, :string, default: nil)
  end

  screen name: :detail do
    scroll padding: 16 do
      text("Detail Screen", text_size: :xl, font_weight: "bold")
      text("This is a pushed screen in the navigation stack.")
      divider()

      # List of items
      text("Select an item:", text_size: :lg)

      for item <- @items do
        button(item, on_tap: :select_item)
      end

      text(
        text:
          compute(fn assigns ->
            case assigns[:selected] do
              nil -> "Tap an item to select it"
              item -> "Selected: #{item}"
            end
          end),
        text_size: :sm,
        text_color: "#666"
      )

      spacer(size: 20)

      button("Go Back", on_tap: :go_back)
    end
  end

  def handle_event(:select_item, %{"text" => item}, socket) do
    {:noreply, Dala.Socket.assign(socket, :selected, item)}
  end

  def handle_event(:go_back, _params, socket) do
    {:noreply, Dala.Screen.pop_screen(socket)}
  end
end
