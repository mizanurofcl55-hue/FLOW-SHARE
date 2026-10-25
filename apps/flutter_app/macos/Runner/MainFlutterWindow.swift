import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var platformChannel: FlutterMethodChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    minSize = NSSize(width: 480, height: 640)
    let channel = FlutterMethodChannel(name: "app.flowshare/platform", binaryMessenger: flutterViewController.engine.binaryMessenger)
    platformChannel = channel
    channel.setMethodCallHandler { call, result in
      if call.method == "freeBytes", let args = call.arguments as? [String: Any], let path = args["path"] as? String {
        do {
          let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
          result((attributes[.systemFreeSize] as? NSNumber)?.int64Value)
        } catch { result(FlutterError(code: "fileUnavailable", message: "Cannot read free space", details: nil)) }
      } else if call.method == "transferActive" { result(nil) }
      else { result(FlutterMethodNotImplemented) }
    }

    super.awakeFromNib()
  }
}
