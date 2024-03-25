import Flutter
import UIKit
import FBSDKCoreKit

let PLATFORM_CHANNEL = "flutter_facebook_sdk/methodChannel"
let EVENTS_CHANNEL = "flutter_facebook_sdk/eventChannel"

public class SwiftFlutterFacebookSdkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    var _eventSink: FlutterEventSink?
    var deepLinkUrl: String = ""
    var _queuedLinks = [String]()
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        _eventSink = events
        _queuedLinks.forEach({ events($0) })
        _queuedLinks.removeAll()
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        _eventSink = nil
        return nil
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftFlutterFacebookSdkPlugin()
        
        let channel = FlutterMethodChannel(name: PLATFORM_CHANNEL, binaryMessenger: registrar.messenger())
        
        let eventChannel = FlutterEventChannel(name: EVENTS_CHANNEL, binaryMessenger: registrar.messenger())
        
        eventChannel.setStreamHandler(instance)
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
    }
    
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Settings.setAdvertiserTrackingEnabled(false)
        let launchOptionsForFacebook = launchOptions
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptionsForFacebook
        )
        AppLinkUtility.fetchDeferredAppLink { (url, error) in
            if let error = error {
                print("Error \(error)")
            }
            if let url = url {
                self.deepLinkUrl = url.absoluteString
                self.sendMessageToStream(link: self.deepLinkUrl)
            }
        }
        return true
    }
    
    public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        deepLinkUrl = url.absoluteString
        self.sendMessageToStream(link: deepLinkUrl)
        return ApplicationDelegate.shared.application(application, open: url, sourceApplication: options[.sourceApplication] as? String, annotation: options[.annotation])
    }
    
    public func applicationDidBecomeActive(_ application: UIApplication) {
        AppEvents.activateApp()
    }
    
    func logEvent(contentType: String, contentData: String, contentId: String, currency: String, price: Double, type: String) {
        let parameters: [String: Any] = [
            AppEvents.ParameterName.content.rawValue: contentData,
            AppEvents.ParameterName.contentID.rawValue: contentId,
            AppEvents.ParameterName.contentType.rawValue: contentType,
            AppEvents.ParameterName.currency.rawValue: currency
        ]
        switch type {
        case "addToWishlist":
            AppEvents.logEvent(.addedToWishlist, valueToSum: price, parameters: parameters)
        case "addToCart":
            AppEvents.logEvent(.addedToCart, valueToSum: price, parameters: parameters)
        case "viewContent":
            AppEvents.logEvent(.viewedContent, valueToSum: price, parameters: parameters)
        default:
            break
        }
    }
    
    func logCompleteRegistrationEvent(registrationMethod: String) {
        let parameters: [String: Any] = [
            AppEvents.ParameterName.registrationMethod.rawValue: registrationMethod
        ]
        AppEvents.logEvent(.completedRegistration, parameters: parameters)
    }
    
    func logPurchase(amount: Double, currency: String, parameters: [String: Any]) {
        AppEvents.logPurchase(amount, currency: currency, parameters: parameters)
    }
    
    func logSearchEvent(contentType: String, contentData: String, contentId: String, searchString: String, success: Bool) {
        let parameters: [String: Any] = [
            AppEvents.ParameterName.contentType.rawValue: contentType,
            AppEvents.ParameterName.content.rawValue: contentData,
            AppEvents.ParameterName.contentID.rawValue: contentId,
            AppEvents.ParameterName.searchString.rawValue: searchString,
            AppEvents.ParameterName.success.rawValue: success
        ]
        AppEvents.logEvent(.searched, parameters: parameters)
    }
    
    func logInitiateCheckoutEvent(contentData: String, contentId: String, contentType: String, numItems: Int, paymentInfoAvailable: Bool, currency: String, totalPrice: Double) {
        let parameters: [String: Any] = [
            AppEvents.ParameterName.content.rawValue: contentData,
            AppEvents.ParameterName.contentID.rawValue: contentId,
            AppEvents.ParameterName.contentType.rawValue: contentType,
            AppEvents.ParameterName.numItems.rawValue: numItems,
            AppEvents.ParameterName.paymentInfoAvailable.rawValue: paymentInfoAvailable,
            AppEvents.ParameterName.currency.rawValue: currency
        ]
        AppEvents.logEvent(.initiatedCheckout, valueToSum: totalPrice, parameters: parameters)
    }
    
    func logGenericEvent(args: [String: Any]) {
        guard let eventName = args["eventName"] as? String else { return }
        let valueToSum = args["valueToSum"] as? Double
        let parameters = args["parameters"] as? [String: Any]
        
        if let valueToSum = valueToSum, let parameters = parameters {
            AppEvents.logEvent(AppEvents.Name(eventName), valueToSum: valueToSum, parameters: parameters)
        } else if let parameters = parameters {
            AppEvents.logEvent(AppEvents.Name(eventName), parameters: parameters)
        } else if let valueToSum = valueToSum {
            AppEvents.logEvent(AppEvents.Name(eventName), valueToSum: valueToSum)
        } else {
            AppEvents.logEvent(AppEvents.Name(eventName))
        }
    }
    
    func sendMessageToStream(link: String) {
        guard let eventSink = _eventSink else {
            _queuedLinks.append(link)
            return
        }
        eventSink(link)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "getDeepLinkUrl":
            result(deepLinkUrl)
        case "logViewedContent", "logAddToCart", "logAddToWishlist":
            guard let args = call.arguments as? [String: Any],
                  let contentType = args["contentType"] as? String,
                  let contentData = args["contentData"] as? String,
                  let contentId = args["contentId"] as? String,
                  let currency = args["currency"] as? String,
                  let price = args["price"] as? Double else {
                result(FlutterError(code: "-1", message: "iOS could not extract flutter arguments in method: (sendParams)", details: nil))
                return
            }
            if call.method == "logViewedContent" {
                logEvent(contentType: contentType, contentData: contentData, contentId: contentId, currency: currency, price: price, type: "viewContent")
            } else if call.method == "logAddToCart" {
                logEvent(contentType: contentType, contentData: contentData, contentId: contentId, currency: currency, price: price, type: "addToCart")
            } else if call.method == "logAddToWishlist" {
                logEvent(contentType: contentType, contentData: contentData, contentId: contentId, currency: currency, price: price, type: "addToWishlist")
            }
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
