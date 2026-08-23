defmodule Dala.Platform.DiagTest do
  use ExUnit.Case, async: true

  alias Dala.Platform.Diag

  test "loaded_snapshot/0 reports loaded modules and bundle cross-reference" do
    snap = Diag.loaded_snapshot()

    assert is_integer(snap.loaded_count) and snap.loaded_count > 0
    # This very module must be loaded while running
    assert __MODULE__ in snap.loaded
    assert Map.has_key?(snap, :unloaded_in_bundle)
    assert Map.has_key?(snap, :shipped_count)
    assert %DateTime{} = snap.captured_at
  end

  test "verify_loaded_modules/0 returns a load report" do
    report = Diag.verify_loaded_modules()

    assert %{total: total, loaded: loaded, failed: failed} = report
    assert loaded in 0..total
    assert failed == []

    Enum.each(failed, fn f ->
      assert %{module: m, reason: _} = f
      assert Atom.to_string(m) =~ ~r/\S/
    end)

    assert report.elapsed_us >= 0
    # otp_root is nil when the BEAM isn't a bundled /otp/lib install (host dev)
    if report.otp_root do
      assert String.contains?(report.otp_root, "/otp")
    end
  end

  test "verify_loaded_modules loads nothing extra on host dev (no bundled otp root)" do
    report = Diag.verify_loaded_modules()

    unless report.otp_root do
      assert report.total == 0
      assert report.loaded == 0
      assert report.failed == []
    end
  end
end
