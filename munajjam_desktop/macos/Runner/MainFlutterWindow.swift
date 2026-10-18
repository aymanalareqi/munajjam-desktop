import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    appearance = NSAppearance(named: .darkAqua)
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let lifecycle = FlutterMethodChannel(
      name: "munajjam/lifecycle", binaryMessenger: flutterViewController.engine.binaryMessenger)
    lifecycle.setMethodCallHandler { call, result in
      if call.method == "approveQuit" {
        (NSApp.delegate as? AppDelegate)?.quitApproved = true
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
