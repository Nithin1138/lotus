import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var intakeChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    
    if let controller = engineBridge.pluginRegistry as? FlutterViewController {
      intakeChannel = FlutterMethodChannel(
        name: "com.dropdial.mobile/intake",
        binaryMessenger: controller.binaryMessenger
      )
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.isFileURL {
      intakeChannel?.invokeMethod("onFilesReceived", arguments: [url.path])
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
