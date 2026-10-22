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

    var settings = NotificationSettings()
    var onSessionChanged: ((FocusSession) -> Void)?

    private var timer: Timer?
    private var activeSeconds = 0
    private var focusIntervalSeconds = 0
    private var nagIntervalSeconds = 0
    private var session: FocusSession?

    var displayTime: String {
        let value = phase == .breakTime ? phaseSecondsRemaining : activeSecondsRemaining
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    func requestNotificationAccess() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func start(taskID: UUID?, title: String, activeMinutes: Int) {
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
        startTimer()
    }

    func togglePause() {
        switch phase {
        case .focusing, .breakTime:
            phase = .paused
            stopTimer()
        case .paused:
            phase = phaseSecondsRemaining > 0 ? .breakTime : .focusing
            startTimer()
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
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        switch phase {
        case .focusing:
            activeSecondsRemaining -= 1
            activeSeconds += 1
            focusIntervalSeconds += 1
            nagIntervalSeconds += 1

            if nagIntervalSeconds >= settings.nagIntervalMinutes * 60 {
                nagIntervalSeconds = 0
                notify(title: "Are you doing \(title ?? "your task")?", body: "Return to what you planned to do.")
            }
            if activeSecondsRemaining <= 0 {
                finishSession()
                reset()
            } else if focusIntervalSeconds >= settings.focusIntervalMinutes * 60 {
                focusIntervalSeconds = 0
                phaseSecondsRemaining = settings.breakMinutes * 60
                phase = .breakTime
                notify(title: "Take a \(settings.breakMinutes)-minute break", body: "Your task will resume after the break.")
            }
        case .breakTime:
            phaseSecondsRemaining -= 1
            if phaseSecondsRemaining <= 0 {
                phaseSecondsRemaining = 0
                phase = .focusing
                notify(title: "Break finished", body: "Resume \(title ?? "your task").")
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
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
