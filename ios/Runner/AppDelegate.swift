import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    #if DEBUG
      let googleMapsApiKey = "AIzaSyACaI8ytW1F68P2bQjk3E19FV6GXFGXxHg"
    #else
      let googleMapsApiKey = "AIzaSyDFog7Tzn1kz55dAH6fEBzZhe0V2LzO8pk"
    #endif
    GMSServices.provideAPIKey(googleMapsApiKey)
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "govipservices/runtime_config",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "getGoogleMapsApiKey" {
        result(googleMapsApiKey)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
