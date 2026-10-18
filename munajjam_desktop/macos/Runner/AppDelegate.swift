import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var quitApproved = false

  // Route Cmd+Q, the menu and Dock Quit through the same Dart cleanup as Close.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitApproved || mainFlutterWindow == nil {
      return .terminateNow
    }
    mainFlutterWindow?.performClose(nil)
    return .terminateCancel
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
