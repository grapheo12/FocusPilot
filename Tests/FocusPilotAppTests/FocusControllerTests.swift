import Testing
@preconcurrency import UserNotifications
@testable import FocusPilot
import FocusPilotCore

@MainActor
private final class MockNotifications: NotificationCoordinating {
    var authorizationRequests = 0
    var deliveredLevels: [UNNotificationInterruptionLevel] = []

    func ensureAuthorization() async throws -> Bool {
        authorizationRequests += 1
        return true
    }

    func statusDescription() async -> String {
        "Allowed"
    }

    func deliver(title: String, body: String, interruptionLevel: UNNotificationInterruptionLevel) async throws {
        deliveredLevels.append(interruptionLevel)
    }
}

@Test @MainActor
func focusCountdownTicksAndNagIsTimeSensitive() async {
    let notifications = MockNotifications()
    let focus = FocusController(notifications: notifications)
    focus.settings = NotificationSettings(
        nagIntervalMinutes: 1,
        focusIntervalMinutes: 120,
        breakMinutes: 5
    )

    focus.start(taskID: UUID(), title: "Write tests", activeMinutes: 2)
    #expect(focus.displayTime == "02:00")
    #expect(focus.projectedEnd != nil)

    for _ in 0..<60 {
        focus.advanceOneSecond()
    }
    await Task.yield()

    #expect(focus.displayTime == "01:00")
    #expect(notifications.authorizationRequests >= 1)
    #expect(notifications.deliveredLevels == [.timeSensitive])

    focus.togglePause()
    #expect(focus.phase == .paused)
    #expect(focus.projectedEnd == nil)
    focus.stop()
}
