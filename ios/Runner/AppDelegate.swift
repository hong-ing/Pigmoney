import Flutter
import UIKit
import google_mobile_ads

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let factory = CustomNativeAdFactory()
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "customNativeAd200",
      nativeAdFactory: factory
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
