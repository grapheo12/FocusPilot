import Foundation
import FocusPilotCore
import UserNotifications

struct RunningFocusSession: Identifiable, Equatable {
    var id: UUID { record.id }
    var record: FocusSession
    var activeSecondsRemaining: Int
    var isPaused: Bool

    var displayTime: String {
        String(format: "%02d:%02d", activeSecondsRemaining / 60, activeSecondsRemaining % 60)
    }
}

@MainActor
final class FocusController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case focusing
        case breakTime
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var runningSessions: [RunningFocusSession] = []
    @Published private(set) var breakSecondsRemaining = 0

    var settings = NotificationSettings()
    var onSessionStarted: ((FocusSession) -> Void)?
    var onSessionFinished: ((FocusSession) -> Void)?
    var onProjectionChanged: (() -> Void)?
    var onNotificationError: ((String) -> Void)?

    private var timer: Timer?
    private var sharedFocusSeconds = 0
    private var sharedNagSeconds = 0
    private let notifications: any NotificationCoordinating

    init(notifications: any NotificationCoordinating = NotificationCoordinator.shared) {
        self.notifications = notifications
    }

    var activeSessionCount: Int {
        runningSessions.filter { !$0.isPaused }.count
    }

    var sharedBreakDisplayTime: String {
        String(format: "%02d:%02d", breakSecondsRemaining / 60, breakSecondsRemaining % 60)
    }

    func requestNotificationAccess() async throws -> Bool {
        try await notifications.ensureAuthorization()
    }

    func notificationStatusDescription() async -> String {
        await notifications.statusDescription()
    }

    func sendTestNag() async throws {
        try await notifications.deliver(
            title: "Are you working on your current tasks?",
            body: "This is a test of FocusPilot's Time Sensitive reminders.",
            interruptionLevel: .timeSensitive
        )
    }

    func contains(approvedBlockID: UUID) -> Bool {
        runningSessions.contains { $0.record.approvedBlockID == approvedBlockID }
    }

    func session(for approvedBlockID: UUID) -> RunningFocusSession? {
        runningSessions.first { $0.record.approvedBlockID == approvedBlockID }
    }

    func start(
        approvedBlockID: UUID,
        taskID: UUID?,
        title: String,
        activeSeconds: Int,
        existingSession: FocusSession? = nil
    ) {
        guard activeSeconds > 0, !contains(approvedBlockID: approvedBlockID) else { return }
        var record = existingSession ?? FocusSession(
            taskID: taskID,
            approvedBlockID: approvedBlockID,
            title: title
        )
        record.taskID = taskID
        record.approvedBlockID = approvedBlockID
        record.title = title
        record.endedAt = nil
        runningSessions.append(RunningFocusSession(
            record: record,
            activeSecondsRemaining: activeSeconds,
            isPaused: false
        ))
        if phase == .idle {
            phase = .focusing
        }
        startTimer()
        if existingSession == nil {
            onSessionStarted?(record)
        }
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

    func togglePause(sessionID: UUID) {
        guard let index = runningSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        runningSessions[index].isPaused.toggle()
        onProjectionChanged?()
    }

    func stop(sessionID: UUID) {
        finishSession(sessionID: sessionID)
    }

    func stopAll() {
        for id in runningSessions.map(\.id) {
            finishSession(sessionID: id)
        }
    }

    func projectedEnd(for sessionID: UUID, now: Date = .now) -> Date? {
        guard let session = runningSessions.first(where: { $0.id == sessionID }), !session.isPaused else { return nil }
        let intervalSeconds = max(1, settings.focusIntervalMinutes * 60)
        let breakSeconds = settings.breakMinutes * 60
        let initialDelay: Int
        let focusAlreadyAccumulated: Int
        if phase == .breakTime {
            initialDelay = breakSecondsRemaining
            focusAlreadyAccumulated = 0
        } else {
            initialDelay = 0
            focusAlreadyAccumulated = sharedFocusSeconds
        }
        let secondsUntilNextBreak = max(1, intervalSeconds - focusAlreadyAccumulated)
        let futureBreaks: Int
        if session.activeSecondsRemaining <= secondsUntilNextBreak {
            futureBreaks = 0
        } else {
            futureBreaks = 1 + (session.activeSecondsRemaining - secondsUntilNextBreak - 1) / intervalSeconds
        }
        return now.addingTimeInterval(TimeInterval(
            initialDelay + session.activeSecondsRemaining + futureBreaks * breakSeconds
        ))
    }

    func advanceOneSecond() {
        switch phase {
        case .idle:
            return
        case .breakTime:
            breakSecondsRemaining -= 1
            if breakSecondsRemaining <= 0 {
                breakSecondsRemaining = 0
                phase = runningSessions.isEmpty ? .idle : .focusing
                if !runningSessions.isEmpty {
                    notify(
                        title: "Break finished",
                        body: "Resume your active tasks.",
                        interruptionLevel: .active
                    )
                }
                onProjectionChanged?()
            }
        case .focusing:
            let activeIDs = runningSessions.filter { !$0.isPaused }.map(\.id)
            guard !activeIDs.isEmpty else { return }

            sharedFocusSeconds += 1
            sharedNagSeconds += 1
            for id in activeIDs {
                guard let index = runningSessions.firstIndex(where: { $0.id == id }) else { continue }
                runningSessions[index].activeSecondsRemaining -= 1
                runningSessions[index].record.activeSeconds += 1
            }

            let completed = runningSessions
                .filter { $0.activeSecondsRemaining <= 0 }
                .map(\.id)
            for id in completed {
                finishSession(sessionID: id)
            }
            guard !runningSessions.isEmpty else { return }

            if sharedNagSeconds >= settings.nagIntervalMinutes * 60 {
                sharedNagSeconds = 0
                sendCombinedNag()
            }
            if sharedFocusSeconds >= settings.focusIntervalMinutes * 60,
               runningSessions.contains(where: { !$0.isPaused }) {
                sharedFocusSeconds = 0
                breakSecondsRemaining = settings.breakMinutes * 60
                phase = .breakTime
                notify(
                    title: "Take a \(settings.breakMinutes)-minute break",
                    body: "All active task clocks are paused during this shared break.",
                    interruptionLevel: .active
                )
                onProjectionChanged?()
            }
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceOneSecond() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func finishSession(sessionID: UUID) {
        guard let index = runningSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var session = runningSessions.remove(at: index).record
        session.endedAt = .now
        onSessionFinished?(session)
        if runningSessions.isEmpty {
            stopTimer()
            phase = .idle
            breakSecondsRemaining = 0
            sharedFocusSeconds = 0
            sharedNagSeconds = 0
        }
        onProjectionChanged?()
    }

    private func sendCombinedNag() {
        let titles = runningSessions.filter { !$0.isPaused }.map { $0.record.title }
        guard !titles.isEmpty else { return }
        let title = titles.count == 1
            ? "Are you working on \(titles[0])?"
            : "Are you working on your active tasks?"
        let visibleTitles = titles.prefix(3).joined(separator: ", ")
        let suffix = titles.count > 3 ? " and \(titles.count - 3) more" : ""
        notify(
            title: title,
            body: "Active now: \(visibleTitles)\(suffix).",
            interruptionLevel: .timeSensitive
        )
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
