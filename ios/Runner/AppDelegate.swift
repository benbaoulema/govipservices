import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pendingDeepLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let launchURL = launchOptions?[.url] as? URL {
      pendingDeepLink = launchURL.absoluteString
    }
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
    let liveActivitiesChannel = FlutterMethodChannel(
      name: "govipservices/live_activities",
      binaryMessenger: controller.binaryMessenger
    )
    let deepLinksChannel = FlutterMethodChannel(
      name: "govipservices/deep_links",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "getGoogleMapsApiKey" {
        result(googleMapsApiKey)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    liveActivitiesChannel.setMethodCallHandler { call, result in
      LiveActivityManager.shared.handle(
        method: call.method,
        arguments: call.arguments,
        result: result
      )
    }
    deepLinksChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      if call.method == "getInitialLink" {
        result(self.pendingDeepLink)
        self.pendingDeepLink = nil
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    pendingDeepLink = url.absoluteString
    if let controller = window?.rootViewController as? FlutterViewController {
      let deepLinksChannel = FlutterMethodChannel(
        name: "govipservices/deep_links",
        binaryMessenger: controller.binaryMessenger
      )
      deepLinksChannel.invokeMethod("onDeepLink", arguments: pendingDeepLink)
      pendingDeepLink = nil
    }
    return super.application(app, open: url, options: options)
  }
}
