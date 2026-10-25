import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var platformChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FlowSharePlatform") else { return }
    let channel = FlutterMethodChannel(name: "app.flowshare/platform", binaryMessenger: registrar.messenger())
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
  }
}
