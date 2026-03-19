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
      GMSServices.provideAPIKey("AIzaSyACaI8ytW1F68P2bQjk3E19FV6GXFGXxHg")
    #else
      GMSServices.provideAPIKey("AIzaSyDFog7Tzn1kz55dAH6fEBzZhe0V2LzO8pk")
    #endif
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
