defmodule Dala.App.AppTest do
  use ExUnit.Case, async: true

  alias Dala.App.App

  defmodule ValidScreen do
    def render(_socket), do: %{type: :column, props: %{}, children: []}
  end

  defmodule NotAScreen do
    def render, do: :nope
  end

  defmodule MinimalApp do
    use Dala.App

    def navigation(_platform) do
      stack(:home, root: ValidScreen)
    end
  end

  describe "stack/2" do
    test "builds a stack map" do
      assert %{
               type: :stack,
               name: :home,
               root: ValidScreen,
               title: nil
             } = App.stack(:home, root: ValidScreen)
    end

    test "accepts an optional title" do
      assert %{title: "Home"} = App.stack(:home, root: ValidScreen, title: "Home")
    end

    test "requires :root" do
      assert_raise(KeyError, fn -> App.stack(:home, []) end)
    end
  end

  describe "tab_bar/1 and drawer/1" do
    test "wrap named stacks in the matching container map" do
      branches = [App.stack(:a, root: ValidScreen), App.stack(:b, root: ValidScreen)]

      assert %{type: :tab_bar, branches: ^branches} = App.tab_bar(branches)
      assert %{type: :drawer, branches: ^branches} = App.drawer(branches)
    end
  end

  describe "screens/1" do
    test "returns :ok when every module renders" do
      assert :ok == App.screens([ValidScreen])
    end

    test "raises for modules without render/1" do
      assert_raise(ArgumentError, ~r/not a valid Dala.Screen module/, fn ->
        App.screens([NotAScreen])
      end)

      assert_raise(ArgumentError, ~r/not a valid Dala.Screen module/, fn ->
        App.screens([DoesNotExist])
      end)
    end
  end

  describe "use Dala.App" do
    test "provides a no-op on_start default" do
      assert function_exported?(MinimalApp, :on_start, 0)
      assert MinimalApp.on_start() == :ok
    end

    test "navigation helpers are imported into the app module" do
      assert %{type: :stack, name: :home, root: ValidScreen} = MinimalApp.navigation(:ios)
    end
  end
end
