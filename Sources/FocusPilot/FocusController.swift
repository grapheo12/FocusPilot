import Foundation
import FocusPilotCore
import UserNotifications

@MainActor
final class FocusController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case focusing
        case breakTime
        case paused
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var title: String?
    @Published private(set) var taskID: UUID?
    @Published private(set) var activeSecondsRemaining = 0
    @Published private(set) var phaseSecondsRemaining = 0
    @Published private(set) var projectedEnd: Date?

    var settings = NotificationSettings()
    var onSessionChanged: ((FocusSession) -> Void)?
    var onProjectionChanged: (() -> Void)?
    var onNotificationError: ((String) -> Void)?

    private var timer: Timer?
    private var activeSeconds = 0
    private var focusIntervalSeconds = 0
    private var nagIntervalSeconds = 0
    private var session: FocusSession?
    private let notifications: any NotificationCoordinating

    init(notifications: any NotificationCoordinating = NotificationCoordinator.shared) {
        self.notifications = notifications
    }

    var displayTime: String {
        let value = phase == .breakTime ? phaseSecondsRemaining : activeSecondsRemaining
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    func requestNotificationAccess() async throws -> Bool {
        try await notifications.ensureAuthorization()
    }

    func notificationStatusDescription() async -> String {
        await notifications.statusDescription()
    }

    func sendTestNag() async throws {
        try await notifications.deliver(
            title: "Are you working on your current task?",
            body: "This is a test of FocusPilot's Time Sensitive reminders.",
            interruptionLevel: .timeSensitive
        )
    }

    func start(taskID: UUID?, title: String, activeMinutes: Int) {
        if session != nil {
            finishSession()
        }
        stopTimer()
        self.taskID = taskID
        self.title = title
        activeSecondsRemaining = max(1, activeMinutes) * 60
        activeSeconds = 0
        focusIntervalSeconds = 0
        nagIntervalSeconds = 0
        phaseSecondsRemaining = 0
        phase = .focusing
        session = FocusSession(taskID: taskID, title: title)
        projectedEnd = Date.now.addingTimeInterval(TimeInterval(wallSecondsRemaining()))
        startTimer()
        onProjectionChanged?()
        Task {
            do {
                guard try await notifications.ensureAuthorization() else {
                    throw NotificationCoordinatorError.authorizationDenied
                }
            } catch {
                onNotificationError?(error.localizedDescription)
            }
        }
    }

    func togglePause() {
        switch phase {
        case .focusing, .breakTime:
            phase = .paused
            stopTimer()
            projectedEnd = nil
            onProjectionChanged?()
        case .paused:
            phase = phaseSecondsRemaining > 0 ? .breakTime : .focusing
            projectedEnd = Date.now.addingTimeInterval(TimeInterval(wallSecondsRemaining()))
            startTimer()
            onProjectionChanged?()
        case .idle:
            break
        }
    }

    func stop() {
        finishSession()
        reset()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceOneSecond() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func advanceOneSecond() {
        switch phase {
        case .focusing:
            activeSecondsRemaining -= 1
            activeSeconds += 1
            focusIntervalSeconds += 1
            nagIntervalSeconds += 1

            if nagIntervalSeconds >= settings.nagIntervalMinutes * 60 {
                nagIntervalSeconds = 0
                notify(
                    title: "Are you working on \(title ?? "your task")?",
                    body: "Return to what you planned to do.",
                    interruptionLevel: .timeSensitive
                )
            }
            if activeSecondsRemaining <= 0 {
                finishSession()
                reset()
            } else if focusIntervalSeconds >= settings.focusIntervalMinutes * 60 {
                focusIntervalSeconds = 0
                phaseSecondsRemaining = settings.breakMinutes * 60
                phase = .breakTime
                notify(
                    title: "Take a \(settings.breakMinutes)-minute break",
                    body: "Your task will resume after the break.",
                    interruptionLevel: .active
                )
            }
        case .breakTime:
            phaseSecondsRemaining -= 1
            if phaseSecondsRemaining <= 0 {
                phaseSecondsRemaining = 0
                phase = .focusing
                notify(
                    title: "Break finished",
                    body: "Resume \(title ?? "your task").",
                    interruptionLevel: .active
                )
            }
        case .idle, .paused:
            break
        }
    }

    private func finishSession() {
        guard var session else { return }
        session.endedAt = .now
        session.activeSeconds = activeSeconds
        onSessionChanged?(session)
        self.session = nil
    }

    private func reset() {
        stopTimer()
        phase = .idle
        title = nil
        taskID = nil
        activeSecondsRemaining = 0
        phaseSecondsRemaining = 0
        activeSeconds = 0
        projectedEnd = nil
        onProjectionChanged?()
    }

    private func wallSecondsRemaining() -> Int {
        let breakSeconds = settings.breakMinutes * 60
        if phase == .breakTime {
            let futureBreaks = max(0, activeSecondsRemaining - 1) / max(1, settings.focusIntervalMinutes * 60)
            return phaseSecondsRemaining + activeSecondsRemaining + futureBreaks * breakSeconds
        }

        let intervalSeconds = max(1, settings.focusIntervalMinutes * 60)
        let secondsUntilBreak = max(1, intervalSeconds - focusIntervalSeconds)
        guard activeSecondsRemaining > secondsUntilBreak else { return activeSecondsRemaining }
        let secondsAfterFirstBreak = activeSecondsRemaining - secondsUntilBreak
        let futureBreaks = 1 + max(0, secondsAfterFirstBreak - 1) / intervalSeconds
        return activeSecondsRemaining + futureBreaks * breakSeconds
    }

    private func notify(title: String, body: String, interruptionLevel: UNNotificationInterruptionLevel) {
        Task {
            do {
                try await notifications.deliver(
                    title: title,
                    body: body,
                    interruptionLevel: interruptionLevel
                )
            } catch {
                onNotificationError?(error.localizedDescription)
            }
        }
    }
}
