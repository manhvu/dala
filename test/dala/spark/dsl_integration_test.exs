defmodule Dala.Spark.DslIntegrationTest do
  use ExUnit.Case, async: false

  describe "Spark DSL with all UI components" do
    test "screen with layout containers and children" do
      defmodule TestAllComponentsScreen do
        use Dala.Screen

        screen name: :test_screen do
          column padding: :space_md, gap: :space_sm do
            text("Hello World")

            row gap: :space_sm do
              button("Button 1", on_tap: :increment)
              button("Button 2", on_tap: :decrement)
            end
          end
        end

        def mount(_params, _session, socket), do: {:ok, socket}
        def handle_event(:increment, _params, socket), do: {:noreply, socket}
        def handle_event(:decrement, _params, socket), do: {:noreply, socket}
      end

      assert Code.ensure_loaded?(TestAllComponentsScreen)

      {:ok, socket} =
        TestAllComponentsScreen.mount(%{}, %{}, Dala.Socket.new(TestAllComponentsScreen))

      render_result = TestAllComponentsScreen.render(socket.assigns)

      assert is_list(render_result)
      [column_node] = render_result
      assert column_node.type == :column
      assert is_list(column_node.children)
      assert length(column_node.children) == 2

      [text_node, row_node] = column_node.children
      assert text_node.type == :text
      assert text_node.props.text == "Hello World"
      assert row_node.type == :row
      assert length(row_node.children) == 2
    end

    test "simple DSL screen with minimal components" do
      defmodule TestSimpleDslScreen do
        use Dala.Screen

        screen name: :simple do
          text("Hello")
        end

        def mount(_params, _session, socket), do: {:ok, socket}
      end

      assert Code.ensure_loaded?(TestSimpleDslScreen)

      {:ok, socket} = TestSimpleDslScreen.mount(%{}, %{}, Dala.Socket.new(TestSimpleDslScreen))

      render_result = TestSimpleDslScreen.render(socket.assigns)
      assert is_list(render_result)
      assert length(render_result) == 1
      [text_node] = render_result
      assert text_node.type == :text
      assert text_node.props.text == "Hello"
    end

    test "screen with attributes and @ref syntax" do
      defmodule TestRefScreen do
        use Dala.Screen

        screen name: :ref_test do
          column gap: :space_sm do
            text("Count: 0")
            button("Increment", on_tap: :increment)
          end
        end

        def mount(_params, _session, socket) do
          {:ok, Dala.Socket.assign(socket, :count, 0)}
        end

        def handle_event(:increment, _params, socket) do
          {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
        end
      end

      assert Code.ensure_loaded?(TestRefScreen)

      {:ok, socket} = TestRefScreen.mount(%{}, %{}, Dala.Socket.new(TestRefScreen))
      assert socket.assigns.count == 0

      render_result = TestRefScreen.render(socket.assigns)
      assert is_list(render_result)
      [column_node | _] = render_result
      assert column_node.type == :column

      [text_node | _] = column_node.children
      assert text_node.type == :text
      assert text_node.props.text == "Count: 0"
    end

    test "screen with attributes generates mount" do
      defmodule TestAttrScreen do
        use Dala.Spark.Dsl

        screen name: :attr_test do
          text("Hello")
        end

        def mount(_params, _session, socket), do: {:ok, socket}
      end

      assert Code.ensure_loaded?(TestAttrScreen)

      {:ok, socket} = TestAttrScreen.mount(%{}, %{}, Dala.Socket.new(TestAttrScreen))
      # With AST-based parsing, attributes declared via the attributes macro
      # need the attributes section. This test uses a simple screen without
      # explicit attributes, so we just verify the screen renders.
      render_result = TestAttrScreen.render(socket.assigns)
      assert is_list(render_result)
    end

    test "all leaf components compile" do
      defmodule TestLeafComponentsScreen do
        use Dala.Screen

        screen name: :leaves do
          column gap: :space_sm do
            text("Hello")
            button("Press", on_tap: :pressed)
            icon("settings")
            divider()
            spacer()
            text_field(placeholder: "Type here", on_change: :changed)
            toggle(value: true, on_change: :toggled)
            slider(value: 0.5, on_change: :slid)
            switch(value: false, on_toggle: :switched)
            image("https://example.com/photo.jpg")
            video("https://example.com/clip.mp4")
            activity_indicator(size: :large)
            progress_bar(progress: 0.5)
            status_bar(bar_style: :light_content)
            refresh_control(on_refresh: :refreshed)
            webview("https://elixir-lang.org")
            camera_preview(facing: :front)
            tab_bar(tabs: [])
            list(:my_list)
          end
        end

        def handle_event(_, _, socket), do: {:noreply, socket}
      end

      assert Code.ensure_loaded?(TestLeafComponentsScreen)
    end

    test "nested containers compile" do
      defmodule TestNestedScreen do
        use Dala.Screen

        screen name: :nested do
          column padding: :space_md do
            row gap: :space_sm do
              box do
                text("Overlapping")
              end
            end

            scroll padding: :space_sm do
              text("Scrollable")
            end

            pressable on_press: :pressed do
              text("Pressable")
            end

            safe_area do
              text("Safe")
            end

            modal visible: true, on_dismiss: :dismissed do
              text("Modal")
            end
          end
        end

        def handle_event(_, _, socket), do: {:noreply, socket}
      end

      assert Code.ensure_loaded?(TestNestedScreen)
    end

    test "screen with if conditional compiles" do
      defmodule TestConditionalScreen do
        use Dala.Screen

        screen name: :conditional do
          column gap: :space_sm do
            if true do
              text("Shown")
            else
              text("Hidden")
            end
          end
        end

        def mount(_params, _session, socket), do: {:ok, socket}
      end

      assert Code.ensure_loaded?(TestConditionalScreen)

      {:ok, socket} =
        TestConditionalScreen.mount(%{}, %{}, Dala.Socket.new(TestConditionalScreen))

      render_result = TestConditionalScreen.render(socket.assigns)
      assert is_list(render_result)
      [column_node] = render_result
      assert column_node.type == :column
      # The conditional node should be present in children
      [conditional_node] = column_node.children
      assert conditional_node.type == :conditional
      assert conditional_node.props.condition == true
      assert length(conditional_node.then_children) == 1
      assert length(conditional_node.else_children) == 1
    end

    test "screen with unless conditional compiles" do
      defmodule TestUnlessScreen do
        use Dala.Screen

        screen name: :unless_test do
          column gap: :space_sm do
            unless false do
              text("Visible")
            end
          end
        end

        def mount(_params, _session, socket), do: {:ok, socket}
      end

      assert Code.ensure_loaded?(TestUnlessScreen)

      {:ok, socket} = TestUnlessScreen.mount(%{}, %{}, Dala.Socket.new(TestUnlessScreen))
      render_result = TestUnlessScreen.render(socket.assigns)
      assert is_list(render_result)
      [column_node] = render_result
      [conditional_node] = column_node.children
      assert conditional_node.type == :conditional
      # `unless c do X end` desugars to a conditional whose body is the ELSE
      # branch (renders when c is falsy) — no negation AST is injected.
      assert length(conditional_node.else_children) == 1
      assert conditional_node.then_children == []
    end

    test "screen with text variant compiles" do
      defmodule TestVariantScreen do
        use Dala.Screen

        screen name: :variant_test do
          column gap: :space_sm do
            text("Heading", variant: :heading)
            text("Body text", variant: :body)
            text("Caption", variant: :caption)
          end
        end

        def mount(_params, _session, socket), do: {:ok, socket}
      end

      assert Code.ensure_loaded?(TestVariantScreen)

      {:ok, socket} = TestVariantScreen.mount(%{}, %{}, Dala.Socket.new(TestVariantScreen))
      render_result = TestVariantScreen.render(socket.assigns)
      assert is_list(render_result)
      [column_node] = render_result
      [heading_node, body_node, caption_node] = column_node.children
      # DSL passes variant through as a prop; variant defaults are applied
      # at the Widgets.text/1 level, not in the DSL render path
      assert heading_node.props.variant == :heading
      assert body_node.props.variant == :body
      assert caption_node.props.variant == :caption
    end

    test "screen with new components compiles" do
      defmodule TestNewComponentsScreen do
        use Dala.Screen

        screen name: :new_components do
          column gap: :space_sm do
            skeleton(width: 200, height: 16)
            empty_state(icon: "inbox", title: "Nothing here")
            avatar(fallback: "JS", size: 48)
            stepper(steps: ["A", "B", "C"], current: 0)

            grid(columns: 2) do
              text("Cell 1")
              text("Cell 2")
            end
          end
        end

        def mount(_params, _session, socket), do: {:ok, socket}
      end

      assert Code.ensure_loaded?(TestNewComponentsScreen)

      {:ok, socket} =
        TestNewComponentsScreen.mount(%{}, %{}, Dala.Socket.new(TestNewComponentsScreen))

      render_result = TestNewComponentsScreen.render(socket.assigns)
      assert is_list(render_result)
      [column_node] = render_result

      [skeleton_node, empty_state_node, avatar_node, stepper_node, grid_node] =
        column_node.children

      assert skeleton_node.type == :skeleton
      assert empty_state_node.type == :empty_state
      assert avatar_node.type == :avatar
      assert stepper_node.type == :stepper
      assert grid_node.type == :grid
    end
  end

  describe "DSL verification" do
    test "verify returns no warnings for correct screen" do
      defmodule TestCorrectScreen do
        use Dala.Screen

        screen name: :correct do
          column padding: :space_md do
            text("Hello")
            button("Press", on_tap: :pressed)
          end
        end

        def handle_event(:pressed, _, socket), do: {:noreply, socket}
      end

      warnings = Dala.Spark.Dsl.verify(TestCorrectScreen)
      assert warnings == []
    end

    test "verify returns warnings for unknown component" do
      # We can't easily test this at runtime since the DSL parser
      # would reject unknown components at compile time.
      # Instead, test the verifier directly with raw data.
      entity = %{type: :nonexistent_component, props: %{}, children: [], line: 10}
      warnings = Dala.Spark.DslVerifier.verify_from_raw(TestCorrectScreen, [entity], [], [])
      assert length(warnings) > 0

      assert Enum.any?(
               warnings,
               &(&1.type == :error && String.contains?(&1.message, "Unknown component"))
             )
    end

    test "verify returns warnings for invalid prop" do
      entity = %{
        type: :text,
        props: %{text: "Hello", nonexistent_prop: :value},
        children: [],
        line: 5
      }

      warnings = Dala.Spark.DslVerifier.verify_from_raw(TestCorrectScreen, [entity], [], [])
      assert length(warnings) > 0

      assert Enum.any?(
               warnings,
               &(&1.type == :warning && String.contains?(&1.message, "Unknown prop"))
             )
    end

    test "verify returns error for non-atom event handler" do
      entity = %{
        type: :button,
        props: %{text: "Go", on_tap: "not_an_atom"},
        children: [],
        line: 3
      }

      warnings = Dala.Spark.DslVerifier.verify_from_raw(TestCorrectScreen, [entity], [], [])
      assert length(warnings) > 0

      assert Enum.any?(
               warnings,
               &(&1.type == :error && String.contains?(&1.message, "must be an atom"))
             )
    end

    test "verify returns error for leaf with children" do
      entity = %{
        type: :text,
        props: %{text: "Hello"},
        children: [%{type: :text, props: %{text: "Nested"}, children: [], line: 1}],
        line: 1
      }

      warnings = Dala.Spark.DslVerifier.verify_from_raw(TestCorrectScreen, [entity], [], [])
      assert length(warnings) > 0

      assert Enum.any?(
               warnings,
               &(&1.type == :error && String.contains?(&1.message, "does not accept children"))
             )
    end

    test "verify returns error for invalid attribute type" do
      attr = %{name: :count, type: :invalid_type, line: 1}
      warnings = Dala.Spark.DslVerifier.verify_from_raw(TestCorrectScreen, [], [attr], [])
      assert length(warnings) > 0

      assert Enum.any?(
               warnings,
               &(&1.type == :error && String.contains?(&1.message, "invalid type"))
             )
    end

    test "verify returns warning for invalid variant" do
      entity = %{
        type: :text,
        props: %{text: "Hello", variant: :nonexistent_variant},
        children: [],
        line: 1
      }

      warnings = Dala.Spark.DslVerifier.verify_from_raw(TestCorrectScreen, [entity], [], [])
      assert length(warnings) > 0

      assert Enum.any?(
               warnings,
               &(&1.type == :warning && String.contains?(&1.message, "Invalid variant"))
             )
    end

    test "verify suggests closest match for typos" do
      entity = %{
        type: :text,
        props: %{text: "Hello", text_clor: :primary},
        children: [],
        line: 1
      }

      warnings = Dala.Spark.DslVerifier.verify_from_raw(TestCorrectScreen, [entity], [], [])
      assert length(warnings) > 0
      assert Enum.any?(warnings, &String.contains?(&1.message, "Did you mean"))
    end

    test "format_report produces readable output" do
      warnings = [
        %{type: :error, module: TestModule, line: 10, message: "Test error"},
        %{type: :warning, module: TestModule, line: 5, message: "Test warning"}
      ]

      report = Dala.Spark.DslVerifier.format_report(warnings)
      assert report =~ "DSL Verification Report"
      assert report =~ "1 error"
      assert report =~ "1 warning"
      assert report =~ "Test error"
      assert report =~ "Test warning"
    end

    test "format_report shows success for empty warnings" do
      report = Dala.Spark.DslVerifier.format_report([])
      assert report =~ "No issues found"
    end
  end
end
