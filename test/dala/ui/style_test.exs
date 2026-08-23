defmodule Dala.Ui.StyleTest do
  use ExUnit.Case, async: true

  alias Dala.Ui.Style

  test "a new style defaults to empty props" do
    assert %Style{props: %{}} = Style.__struct__()
  end

  test "merge/2 gives keys in b precedence over a" do
    a = %Style{props: %{text_size: :xl, padding: 16}}
    b = %Style{props: %{text_size: :sm, text_color: :white}}

    merged = Style.merge(a, b)

    assert merged.props == %{text_size: :sm, padding: 16, text_color: :white}
  end

  test "put/3 returns a copy with the key set" do
    base = %Style{props: %{background: :primary}}

    styled = Style.put(base, :background, :red_500)

    assert styled.props.background == :red_500
    # original untouched
    assert base.props.background == :primary
  end
end
