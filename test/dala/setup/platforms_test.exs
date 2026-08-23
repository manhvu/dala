defmodule Dala.Setup.PlatformsTest do
  use ExUnit.Case, async: false

  alias Dala.Setup.Android
  alias Dala.Setup.Ios

  # ── Android ─────────────────────────────────────────────────────────────────

  describe "add_dala_bridge_init/1" do
    test "inserts the init call into a Java onCreate", %{tmp: tmp} do
      path = Path.join(tmp, "MainActivity.java")

      File.write!(path, """
      public class MainActivity extends Activity {
          @Override
          protected void onCreate(Bundle savedInstanceState) {
              super.onCreate(savedInstanceState);
          }
      }
      """)

      assert :ok = Android.add_dala_bridge_init(path)
      assert File.read!(path) =~ "DalaBridge.init()"
    end

    test "inserts the init call into a Kotlin onCreate", %{tmp: tmp} do
      path = Path.join(tmp, "MainActivity.kt")

      File.write!(path, """
      class MainActivity : Activity() {
          override fun onCreate(savedInstanceState: Bundle?) {
              super.onCreate(savedInstanceState)
          }
      }
      """)

      assert :ok = Android.add_dala_bridge_init(path)
      assert File.read!(path) =~ "DalaBridge.init()"
    end

    test "is idempotent when the init call is already present", %{tmp: tmp} do
      path = Path.join(tmp, "Main.java")
      content = "void onCreate(Bundle s) { super.onCreate(s); DalaBridge.init(); }"
      File.write!(path, content)

      assert :ok = Android.add_dala_bridge_init(path)
      assert File.read!(path) == content
    end

    test "errors when no onCreate exists", %{tmp: tmp} do
      path = Path.join(tmp, "Plain.java")
      File.write!(path, "public class Plain {}")

      assert {:error, msg} = Android.add_dala_bridge_init(path)
      assert msg =~ "No onCreate method found"
    end
  end

  # ── iOS ─────────────────────────────────────────────────────────────────────

  describe "find_xcode_project/1" do
    test "prefers a workspace over a project", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "App.xcworkspace"))
      File.mkdir_p!(Path.join(tmp, "App.xcodeproj"))

      assert {:ok, path} = Ios.find_xcode_project(tmp)
      assert path =~ ".xcworkspace"
    end

    test "falls back to a bare project", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "App.xcodeproj"))

      assert {:ok, path} = Ios.find_xcode_project(tmp)
      assert path =~ ".xcodeproj"
    end

    test "errors when neither exists", %{tmp: tmp} do
      assert {:error, msg} = Ios.find_xcode_project(tmp)
      assert msg =~ "No Xcode project"
    end
  end

  describe "xcode_project_exists?/1 and bluetooth_files_present?/1" do
    test "report presence accurately", %{tmp: tmp} do
      refute Ios.xcode_project_exists?(tmp)

      File.mkdir_p!(Path.join(tmp, "P.xcodeproj"))
      assert Ios.xcode_project_exists?(tmp)

      required = [
        "DalaBluetoothManager.h",
        "DalaBluetoothManager.m",
        "DalaBluetoothCInterface.m",
        "DalaBluetooth.swift"
      ]

      Enum.each(required, fn f -> File.write!(Path.join(tmp, f), "") end)

      assert Ios.bluetooth_files_present?(tmp)

      File.rm!(Path.join(tmp, "DalaBluetooth.swift"))
      refute Ios.bluetooth_files_present?(tmp)
    end
  end

  setup do
    %{tmp: Path.join(System.tmp_dir!(), "dala_setup_test_#{System.unique_integer([:positive])}")}
  end

  setup %{tmp: tmp} do
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    :ok
  end
end
