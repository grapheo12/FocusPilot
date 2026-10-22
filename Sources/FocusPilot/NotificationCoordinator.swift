import Foundation
@preconcurrency import UserNotifications

@MainActor
protocol NotificationCoordinating: AnyObject {
    func ensureAuthorization() async throws -> Bool
    func statusDescription() async -> String
    func deliver(title: String, body: String, interruptionLevel: UNNotificationInterruptionLevel) async throws
}

@MainActor
final class NotificationCoordinator: NSObject, NotificationCoordinating, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    func ensureAuthorization() async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func statusDescription() async -> String {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            switch settings.timeSensitiveSetting {
            case .enabled:
                return "Notifications and Time Sensitive alerts are allowed."
            case .disabled:
                return "Notifications allowed; Time Sensitive alerts are disabled in System Settings."
            case .notSupported:
                return "Notifications allowed; Time Sensitive delivery requires a Developer-signed build."
            @unknown default:
                return "Notifications are allowed; Time Sensitive status is unavailable."
            }
        case .denied:
            return "Notifications are disabled in System Settings."
        case .notDetermined:
            return "Notification permission has not been requested yet."
        @unknown default:
            return "Notification status is unavailable."
        }
    }

    func deliver(title: String, body: String, interruptionLevel: UNNotificationInterruptionLevel) async throws {
        guard try await ensureAuthorization() else {
            throw NotificationCoordinatorError.authorizationDenied
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = interruptionLevel
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try await center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

enum NotificationCoordinatorError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        "FocusPilot notifications are disabled. Enable them in System Settings > Notifications > FocusPilot."
    }
}
