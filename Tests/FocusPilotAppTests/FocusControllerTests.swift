import Foundation
import Testing
@preconcurrency import UserNotifications
@testable import FocusPilot
import FocusPilotCore

@MainActor
private final class MockNotifications: NotificationCoordinating {
    var authorizationRequests = 0
    var delivered: [(String, String, UNNotificationInterruptionLevel)] = []

    func ensureAuthorization() async throws -> Bool {
        authorizationRequests += 1
        return true
    }

    func statusDescription() async -> String {
        "Allowed"
    }

    func deliver(title: String, body: String, interruptionLevel: UNNotificationInterruptionLevel) async throws {
        delivered.append((title, body, interruptionLevel))
    }
}

@Test @MainActor
func parallelCountdownsSendOneCombinedTimeSensitiveNag() async {
    let notifications = MockNotifications()
    let focus = FocusController(notifications: notifications)
    focus.settings = NotificationSettings(
        nagIntervalMinutes: 1,
        focusIntervalMinutes: 120,
        breakMinutes: 5
    )

    focus.start(
        approvedBlockID: UUID(),
        taskID: UUID(),
        title: "Write tests",
        activeSeconds: 120
    )
    focus.start(
        approvedBlockID: UUID(),
        taskID: UUID(),
        title: "Review patch",
        activeSeconds: 180
    )

    for _ in 0..<60 {
        focus.advanceOneSecond()
    }
    await Task.yield()

    #expect(focus.runningSessions.map(\.activeSecondsRemaining) == [60, 120])
    #expect(notifications.authorizationRequests >= 2)
    #expect(notifications.delivered.count == 1)
    #expect(notifications.delivered[0].2 == .timeSensitive)
    #expect(notifications.delivered[0].1.contains("Write tests"))
    #expect(notifications.delivered[0].1.contains("Review patch"))

    let firstID = focus.runningSessions[0].id
    focus.togglePause(sessionID: firstID)
    focus.advanceOneSecond()
    #expect(focus.runningSessions.first { $0.id == firstID }?.activeSecondsRemaining == 60)
    #expect(focus.runningSessions.first { $0.id != firstID }?.activeSecondsRemaining == 119)
    focus.stopAll()
}

@Test @MainActor
func sharedBreakPausesEveryRunningClock() async {
    let notifications = MockNotifications()
    let focus = FocusController(notifications: notifications)
    focus.settings = NotificationSettings(
        nagIntervalMinutes: 60,
        focusIntervalMinutes: 1,
        breakMinutes: 1
    )
    focus.start(
        approvedBlockID: UUID(),
        taskID: UUID(),
        title: "One",
        activeSeconds: 180
    )
    focus.start(
        approvedBlockID: UUID(),
        taskID: UUID(),
        title: "Two",
        activeSeconds: 180
    )

    for _ in 0..<60 {
        focus.advanceOneSecond()
    }
    #expect(focus.phase == .breakTime)
    #expect(focus.runningSessions.map(\.activeSecondsRemaining) == [120, 120])

    for _ in 0..<60 {
        focus.advanceOneSecond()
    }
    await Task.yield()

    #expect(focus.phase == .focusing)
    #expect(focus.runningSessions.map(\.activeSecondsRemaining) == [120, 120])
    #expect(notifications.delivered.filter { $0.2 == .active }.count == 2)
    focus.stopAll()
}

@Test
func autoStartPolicyTrimsLateTimeAndRejectsExpiredBlocks() {
    let now = Date(timeIntervalSince1970: 10_000)
    let first = ApprovedBlock(
        taskID: UUID(),
        title: "First",
        start: now.addingTimeInterval(-120),
        end: now.addingTimeInterval(3_600),
        activeMinutes: 10,
        kind: .task
    )
    let second = ApprovedBlock(
        taskID: UUID(),
        title: "Second",
        start: now,
        end: now.addingTimeInterval(3_600),
        activeMinutes: 5,
        kind: .task
    )
    var expired = first
    expired.end = now

    #expect(AutoStartPolicy.remainingActiveSeconds(for: first, at: now) == 480)
    #expect(AutoStartPolicy.remainingActiveSeconds(for: second, at: now) == 300)
    #expect(AutoStartPolicy.remainingActiveSeconds(for: expired, at: now) == nil)
}
