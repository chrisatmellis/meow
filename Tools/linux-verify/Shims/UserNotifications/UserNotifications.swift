// Linux typecheck shim mirroring the UserNotifications API surface the game uses.
@_exported import Foundation

public struct UNAuthorizationOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNAuthorizationOptions(rawValue: 1)
    public static let sound = UNAuthorizationOptions(rawValue: 2)
    public static let alert = UNAuthorizationOptions(rawValue: 4)
    public static let provisional = UNAuthorizationOptions(rawValue: 64)
}

public enum UNAuthorizationStatus: Int {
    case notDetermined, denied, authorized, provisional, ephemeral
}

open class UNNotificationSound: NSObject {
    public static let `default` = UNNotificationSound()
}

open class UNNotificationContent: NSObject {
    open var title: String { "" }
    open var body: String { "" }
}

open class UNMutableNotificationContent: UNNotificationContent {
    public override init() { super.init() }
    open override var title: String {
        get { "" }
        set {}
    }
    open override var body: String {
        get { "" }
        set {}
    }
    open var subtitle: String = ""
    open var sound: UNNotificationSound?
    open var badge: NSNumber?
    open var categoryIdentifier: String = ""
    open var threadIdentifier: String = ""
    open var userInfo: [AnyHashable: Any] = [:]
}

open class UNNotificationTrigger: NSObject {}

open class UNTimeIntervalNotificationTrigger: UNNotificationTrigger {
    public init(timeInterval: TimeInterval, repeats: Bool) {}
}

open class UNCalendarNotificationTrigger: UNNotificationTrigger {
    public init(dateMatching dateComponents: DateComponents, repeats: Bool) {}
}

open class UNNotificationRequest: NSObject {
    public init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {}
}

open class UNNotificationSettings: NSObject {
    open var authorizationStatus: UNAuthorizationStatus { .notDetermined }
}

open class UNUserNotificationCenter: NSObject {
    open class func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }
    open func requestAuthorization(options: UNAuthorizationOptions,
                                   completionHandler: @escaping (Bool, Error?) -> Void) {}
    open func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void) {}
    open func add(_ request: UNNotificationRequest, withCompletionHandler: ((Error?) -> Void)?) {}
    open func removeAllPendingNotificationRequests() {}
    open func removeAllDeliveredNotifications() {}
    open func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void) {}
}
