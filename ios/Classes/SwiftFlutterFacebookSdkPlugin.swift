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
        Settings.shared.isAdvertiserTrackingEnabled = false
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
        AppEvents.shared.activateApp()
    }
    
    func logEvent(contentType: String, contentData: String, contentId: String, currency: String, price: Double, type: String) {
        let parameters: [AppEvents.ParameterName: Any] = [
            .content: contentData,
            .contentID: contentId,
            .contentType: contentType,
            .currency: currency
        ]
        switch type {
        case "addToWishlist":
            AppEvents.shared.logEvent(.addedToWishlist, valueToSum: price, parameters: parameters)
        case "addToCart":
            AppEvents.shared.logEvent(.addedToCart, valueToSum: price, parameters: parameters)
        case "viewContent":
            AppEvents.shared.logEvent(.viewedContent, valueToSum: price, parameters: parameters)
        default:
            break
        }
    }
    
    func logCompleteRegistrationEvent(registrationMethod: String) {
        let parameters: [AppEvents.ParameterName: Any] = [
            .registrationMethod: registrationMethod
        ]
        AppEvents.shared.logEvent(.completedRegistration, parameters: parameters)
    }
    
    func logPurchase(amount: Double, currency: String, parameters: [String: Any]) {
        var convertedParams: [AppEvents.ParameterName: Any] = [:]
        for (key, value) in parameters {
            convertedParams[AppEvents.ParameterName(key)] = value
        }
        AppEvents.shared.logPurchase(amount, currency: currency, parameters: convertedParams)
    }
    
    func logSearchEvent(contentType: String, contentData: String, contentId: String, searchString: String, success: Bool) {
        let parameters: [AppEvents.ParameterName: Any] = [
            .contentType: contentType,
            .content: contentData,
            .contentID: contentId,
            .searchString: searchString,
            .success: NSNumber(value: success)
        ]
        AppEvents.shared.logEvent(.searched, parameters: parameters)
    }
    
    func logInitiateCheckoutEvent(contentData: String, contentId: String, contentType: String, numItems: Int, paymentInfoAvailable: Bool, currency: String, totalPrice: Double) {
        let parameters: [AppEvents.ParameterName: Any] = [
            .content: contentData,
            .contentID: contentId,
            .contentType: contentType,
            .numItems: NSNumber(value: numItems),
            .paymentInfoAvailable: NSNumber(value: paymentInfoAvailable),
            .currency: currency
        ]
        AppEvents.shared.logEvent(.initiatedCheckout, valueToSum: totalPrice, parameters: parameters)
    }
    
    func logGenericEvent(args: [String: Any]) {
        guard let eventName = args["eventName"] as? String else { return }
        let valueToSum = args["valueToSum"] as? Double
        let parameters = args["parameters"] as? [String: Any]
        
        var convertedParams: [AppEvents.ParameterName: Any]?
        if let parameters = parameters {
            convertedParams = [:]
            for (key, value) in parameters {
                convertedParams?[AppEvents.ParameterName(key)] = value
            }
        }
        
        if let valueToSum = valueToSum, let convertedParams = convertedParams {
            AppEvents.shared.logEvent(AppEvents.Name(eventName), valueToSum: valueToSum, parameters: convertedParams)
        } else if let convertedParams = convertedParams {
            AppEvents.shared.logEvent(AppEvents.Name(eventName), parameters: convertedParams)
        } else if let valueToSum = valueToSum {
            AppEvents.shared.logEvent(AppEvents.Name(eventName), valueToSum: valueToSum)
        } else {
            AppEvents.shared.logEvent(AppEvents.Name(eventName))
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
