import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var flutterEngine: FlutterEngine?

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  // 与 Windows 一样不预建 Flutter 窗口，改由 Dart RegularWindow 创建，便于以后在 Mac 上拆分终端。
  override func applicationDidFinishLaunching(_ notification: Notification) {
    let engine = FlutterEngine(name: "ssh_flutter", project: nil)
    RegisterGeneratedPlugins(registry: engine)
    engine.run(withEntrypoint: nil)
    flutterEngine = engine
  }
}
