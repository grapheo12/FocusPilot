import AppKit
import Combine
import Foundation
import FocusPilotCore
import FocusPilotPlanner
import FocusPilotVault
import ServiceManagement
import WidgetKit

enum AutoStartPolicy {
    static func remainingActiveSeconds(for block: ApprovedBlock, at now: Date) -> Int? {
        guard block.start <= now, block.end > now else { return nil }
        let elapsedSeconds = max(0, Int(now.timeIntervalSince(block.start)))
        let remainingSeconds = block.activeMinutes * 60 - elapsedSeconds
        return remainingSeconds > 0 ? remainingSeconds : nil
    }
}

enum PlanVisibility {
    static func approvedBlocks(in state: AppState) -> [ApprovedBlock] {
        state.approvedBlocks.values.filter { block in
            guard let taskID = block.taskID else { return true }
            return state.tasks[taskID]?.isCompleted == false
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state = AppState()
    @Published var proposals: [ProposedBlock] = []
    @Published var unscheduledTaskIDs = Set<UUID>()
    @Published var errorMessage: String?
    @Published var vaultReady = false
    @Published var isBusy = false
    @Published var hideWidgetTitles = false {
        didSet { writeWidgetProjection() }
    }
    @Published private(set) var widgetSyncStatus = "Waiting for the vault to open."
    @Published private(set) var widgetLastUpdated: Date?
    @Published var lastCompactionMessage: String?
    @Published var startAtLogin = SMAppService.mainApp.status == .enabled

    let calendarService: CalendarService
    let focus: FocusController

    private var vault: VaultStore?
    private var vaultKey: Data?
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private var scheduleTimer: Timer?
    private var handledBlockIDs = Set<UUID>()
    private var projectedCurrentBlockIDs = Set<UUID>()

    private var deviceID: UUID {
        if let value = defaults.string(forKey: "deviceID"), let id = UUID(uuidString: value) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: "deviceID")
        return id
    }

    var incompleteTasks: [TaskItem] {
        state.tasks.values.filter { !$0.isCompleted }.sorted { $0.createdAt < $1.createdAt }
    }

    var rootTasks: [TaskItem] {
        state.tasks.values.filter { $0.parentID == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    var currentApprovedBlocks: [ApprovedBlock] {
        let now = Date.now
        return approvedBlocksForPlan
            .filter { $0.start <= now && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    var approvedBlocksForPlan: [ApprovedBlock] {
        PlanVisibility.approvedBlocks(in: state)
    }

    var currentApprovedBlock: ApprovedBlock? {
        currentApprovedBlocks.first
    }

    var nextApprovedBlock: ApprovedBlock? {
        approvedBlocksForPlan.filter { $0.start > .now }.sorted { $0.start < $1.start }.first
    }

    var menuTitle: String {
        if focus.runningSessions.count == 1, let session = focus.runningSessions.first {
            return "\(session.record.title) · \(session.displayTime)"
        }
        if focus.runningSessions.count > 1 {
            return "\(focus.runningSessions.count) active tasks"
        }
        if let block = currentApprovedBlock { return block.title }
        return nextApprovedBlock.map { "Next: \($0.title)" } ?? "FocusPilot"
    }

    init(
        calendarService: CalendarService = CalendarService(),
        focus: FocusController = FocusController(),
        restoreVault: Bool = true
    ) {
        self.calendarService = calendarService
        self.focus = focus
        focus.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        focus.onSessionStarted = { [weak self] session in
            self?.persistStartedSession(session)
        }
        focus.onSessionFinished = { [weak self] session in
            self?.persistFinishedSession(session)
        }
        focus.onProjectionChanged = { [weak self] in
            self?.writeWidgetProjection()
        }
        focus.onNotificationError = { [weak self] message in
            self?.errorMessage = message
        }
        calendarService.$revision
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshPlan() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshPlan() }
            }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshPlan() }
            }
            .store(in: &cancellables)
        if restoreVault {
            Task { await restoreVaultIfPossible() }
        }
    }

    func children(of parentID: UUID) -> [TaskItem] {
        state.tasks.values.filter { $0.parentID == parentID }.sorted { $0.createdAt < $1.createdAt }
    }

    func createVault(at url: URL) async {
        await perform {
            let (store, key) = try await VaultStore.create(repositoryURL: url, deviceID: self.deviceID)
            let vaultID = await store.vaultID
            try VaultKeyStore.save(key, vaultID: vaultID)
            self.vault = store
            self.vaultKey = key
            self.defaults.set(url.path, forKey: "vaultPath")
            self.defaults.set(vaultID.uuidString, forKey: "vaultID")
            self.state = await store.currentState()
            self.vaultReady = true
            self.startScheduleTimer()
            self.checkAutoStarts()
            self.writeWidgetProjection()
        }
    }

    func openVault(at url: URL, recoveryFile: URL? = nil) async {
        await perform {
            let manifestURL = url.appending(path: "vault/manifest.json")
            let manifest = try JSONDecoder.vaultDecoder.decode(VaultManifest.self, from: Data(contentsOf: manifestURL))
            var key = try VaultKeyStore.load(vaultID: manifest.vaultID)
            if key == nil, let recoveryFile {
                let recovery = try VaultKeyStore.importFile(from: recoveryFile)
                guard recovery.vaultID == manifest.vaultID else { throw KeyStoreError.invalidRecoveryFile }
                key = recovery.keyData
                try VaultKeyStore.save(key!, vaultID: manifest.vaultID)
            }
            guard let key else { throw KeyStoreError.invalidRecoveryFile }
            let store = try await VaultStore.open(repositoryURL: url, key: key, deviceID: self.deviceID)
            self.vault = store
            self.vaultKey = key
            self.defaults.set(url.path, forKey: "vaultPath")
            self.defaults.set(manifest.vaultID.uuidString, forKey: "vaultID")
            self.state = await store.currentState()
            self.focus.settings = self.state.notificationSettings
            self.vaultReady = true
            await self.refreshPlan()
            self.startScheduleTimer()
            self.checkAutoStarts()
            self.writeWidgetProjection()
        }
    }

    func addTask(title: String, parentID: UUID? = nil) async {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let task = TaskItem(parentID: parentID, title: clean)
        guard await mutate(.upsertTask(task)) else { return }
        await approve(proposals.filter { $0.taskID == task.id })
    }

    func saveTask(_ task: TaskItem) async {
        var changed = task
        changed.updatedAt = .now
        await mutate(.upsertTask(changed))
    }

    func toggleTask(_ task: TaskItem) async {
        var changed = task
        changed.isCompleted.toggle()
        changed.updatedAt = .now
        var mutations: [VaultMutation] = [.upsertTask(changed)]
        let runningSessionIDs = focus.runningSessions
            .filter { $0.record.taskID == changed.id }
            .map(\.id)

        if changed.isCompleted {
            mutations.append(.addCompletionRecord(.init(taskID: changed.id)))
            mutations.append(contentsOf: state.approvedBlocks.values
                .filter { $0.taskID == changed.id }
                .map { .deleteApprovedBlock($0.id) })
        }

        guard await mutate(mutations) else { return }
        if changed.isCompleted {
            for sessionID in runningSessionIDs {
                focus.stop(sessionID: sessionID)
            }
        }
    }

    func deleteTask(_ task: TaskItem) async {
        for child in children(of: task.id) {
            var reparented = child
            reparented.parentID = task.parentID
            await saveTask(reparented)
        }
        await mutate(.deleteTask(task.id))
    }

    func weeklyCommitment(for taskID: UUID) -> WeeklyCommitment? {
        state.weeklyCommitments.values.first { $0.taskID == taskID }
    }

    func saveWeeklyCommitment(taskID: UUID, targetMinutes: Int) async {
        if let existing = weeklyCommitment(for: taskID) {
            if targetMinutes <= 0 {
                await mutate(.deleteWeeklyCommitment(existing.id))
            } else {
                var changed = existing
                changed.targetMinutes = targetMinutes
                await mutate(.upsertWeeklyCommitment(changed))
            }
        } else if targetMinutes > 0 {
            await mutate(.upsertWeeklyCommitment(.init(taskID: taskID, targetMinutes: targetMinutes)))
        }
    }

    func approve(_ proposal: ProposedBlock) async {
        await approve([proposal])
    }

    func approveAll() async {
        await approve(proposals.filter { $0.kind == .task })
    }

    func saveApprovedBlock(_ block: ApprovedBlock) async {
        guard block.calendarEventReference == nil, block.end > block.start else { return }
        var changed = block
        let wallMinutes = max(1, Int(block.end.timeIntervalSince(block.start) / 60))
        changed.activeMinutes = max(
            1,
            FocusTiming.activeMinutes(
                fittingWallMinutes: wallMinutes,
                settings: state.notificationSettings
            )
        )
        await mutate(.upsertApprovedBlock(changed))
    }

    func start(_ block: ApprovedBlock) {
        focus.settings = state.notificationSettings
        handledBlockIDs.insert(block.id)
        focus.start(
            approvedBlockID: block.id,
            taskID: block.taskID,
            title: block.title,
            activeSeconds: block.activeMinutes * 60
        )
        writeWidgetProjection()
    }

    func startCurrentBlock() {
        let block = currentApprovedBlocks.first { !focus.contains(approvedBlockID: $0.id) }
            ?? nextApprovedBlock
        guard let block else { return }
        start(block)
    }

    func toggleFocusPause(sessionID: UUID) {
        focus.togglePause(sessionID: sessionID)
    }

    func stopFocus(sessionID: UUID) {
        focus.stop(sessionID: sessionID)
    }

    func requestNotificationAccess() async {
        do {
            guard try await focus.requestNotificationAccess() else {
                throw NotificationCoordinatorError.authorizationDenied
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestCalendarAccess() async {
        do {
            guard try await calendarService.requestAccess() else {
                errorMessage = calendarService.authorizationDescription
                return
            }
            await refreshPlan()
        } catch {
            calendarService.refreshAuthorizationStatus()
            errorMessage = "Calendar access could not be requested: \(error.localizedDescription)"
        }
    }

    func sendTestNotification() async {
        do {
            try await focus.sendTestNag()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func notificationStatusDescription() async -> String {
        await focus.notificationStatusDescription()
    }

    func refreshPlan() async {
        guard vaultReady else { return }
        let now = Date.now
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let latestLinkedEnd = state.approvedBlocks.values
            .filter { $0.calendarEventReference != nil && $0.end > now }
            .map(\.end)
            .max() ?? end
        let reconciliationEnd = Calendar.current.date(
            byAdding: .day,
            value: 7,
            to: max(end, latestLinkedEnd)
        ) ?? max(end, latestLinkedEnd)
        let queryStart = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let calendarEvents = calendarService.events(from: queryStart, to: reconciliationEnd)
        await reconcileCalendarBlocks(with: calendarEvents, now: now)
        let planningEvents = calendarEvents.filter { $0.end > now && $0.start < end }
        let busy = calendarService.busyIntervals(from: planningEvents)
        let result = TaskPlanner().generate(.init(
            now: now,
            tasks: Array(state.tasks.values),
            commitments: Array(state.weeklyCommitments.values),
            approvedBlocks: approvedBlocksForPlan,
            completionRecords: Array(state.completionRecords.values),
            busyIntervals: busy,
            settings: state.plannerSettings,
            notificationSettings: state.notificationSettings
        ))
        let calendarProposals = planningEvents
            .filter { event in
                !state.approvedBlocks.values.contains { block in
                    guard let reference = block.calendarEventReference else { return false }
                    return calendarService.representsSameOccurrence(reference: reference, event: event)
                }
            }
            .map { event in
                ProposedBlock(
                    taskID: nil,
                    title: event.title,
                    start: event.start,
                    end: event.end,
                    activeMinutes: max(1, Int(event.end.timeIntervalSince(event.start) / 60)),
                    kind: .calendarEvent,
                    calendarEventReference: event.reference
                )
            }
        proposals = (result.proposals + calendarProposals).sorted { $0.start < $1.start }
        unscheduledTaskIDs = result.unscheduledTaskIDs
        checkAutoStarts(at: now)
    }

    func updateNotificationSettings(_ settings: NotificationSettings) async {
        focus.settings = settings
        await mutate(.updateNotificationSettings(settings))
    }

    func updatePlannerSettings(_ settings: PlannerSettings) async {
        await mutate(.updatePlannerSettings(settings))
    }

    func setStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            startAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            startAtLogin = SMAppService.mainApp.status == .enabled
            errorMessage = error.localizedDescription
        }
    }

    func compact() async {
        await perform {
            guard let vault = self.vault else { return }
            let report = try await vault.compact(force: true)
            self.lastCompactionMessage = "Deleted \(report.prunedOperations) operation files and \(report.prunedSnapshots) old snapshots. Git history was preserved."
        }
    }

    func sync() async {
        await perform {
            guard let vault = self.vault else { return }
            self.state = try await vault.sync()
            await self.refreshPlan()
            self.writeWidgetProjection()
        }
    }

    func exportRecoveryKey(to url: URL) {
        guard let vault, let vaultKey else { return }
        Task {
            do {
                let id = await vault.vaultID
                try VaultKeyStore.exportFile(vaultID: id, key: vaultKey, to: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restoreVaultIfPossible() async {
        guard let path = defaults.string(forKey: "vaultPath") else { return }
        await openVault(at: URL(fileURLWithPath: path))
    }

    @discardableResult
    private func mutate(_ mutation: VaultMutation) async -> Bool {
        await mutate([mutation])
    }

    @discardableResult
    private func mutate(_ mutations: [VaultMutation]) async -> Bool {
        guard !mutations.isEmpty else { return true }
        return await perform {
            guard let vault = self.vault else { return }
            for mutation in mutations {
                try await vault.append(mutation)
            }
            self.state = await vault.currentState()
            self.writeWidgetProjection()
            await self.refreshPlan()
        }
    }

    private func approve(_ selected: [ProposedBlock]) async {
        guard !selected.isEmpty else { return }
        let previous = proposals
        let selectedIDs = Set(selected.map(\.id))
        proposals.removeAll { selectedIDs.contains($0.id) }

        let succeeded = await perform {
            guard let vault = self.vault else { return }
            for proposal in selected {
                try await vault.append(.upsertApprovedBlock(.init(proposal: proposal)))
            }
            self.state = await vault.currentState()
            self.writeWidgetProjection()
            await self.refreshPlan()
        }
        if !succeeded {
            proposals = previous
        }
    }

    private func persistStartedSession(_ session: FocusSession) {
        Task { await mutate(.upsertFocusSession(session)) }
    }

    private func persistFinishedSession(_ session: FocusSession) {
        Task {
            await mutate(.upsertFocusSession(session))
            if let taskID = session.taskID {
                await mutate(.addCompletionRecord(.init(taskID: taskID, activeMinutes: session.activeSeconds / 60)))
            }
        }
    }

    func checkAutoStarts(at now: Date = .now) {
        guard vaultReady else { return }
        let dueBlocks = approvedBlocksForPlan
            .filter { $0.start <= now && $0.end > now }
            .sorted { $0.start < $1.start }
        let currentBlockIDs = Set(dueBlocks.map(\.id))
        let currentBlocksChanged = currentBlockIDs != projectedCurrentBlockIDs
        projectedCurrentBlockIDs = currentBlockIDs

        for block in dueBlocks {
            guard !focus.contains(approvedBlockID: block.id),
                  !handledBlockIDs.contains(block.id) else { continue }
            let sessions = state.focusSessions.values
                .filter { $0.approvedBlockID == block.id }
                .sorted { $0.startedAt < $1.startedAt }
            if sessions.contains(where: { $0.endedAt != nil }) {
                handledBlockIDs.insert(block.id)
                continue
            }

            guard let remainingSeconds = AutoStartPolicy.remainingActiveSeconds(for: block, at: now) else {
                handledBlockIDs.insert(block.id)
                continue
            }

            handledBlockIDs.insert(block.id)
            focus.settings = state.notificationSettings
            focus.start(
                approvedBlockID: block.id,
                taskID: block.taskID,
                title: block.title,
                activeSeconds: remainingSeconds,
                existingSession: sessions.first(where: { $0.endedAt == nil })
            )
        }
        if currentBlocksChanged {
            writeWidgetProjection()
        }
    }

    private func startScheduleTimer() {
        guard scheduleTimer == nil else { return }
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAutoStarts() }
        }
        RunLoop.main.add(scheduleTimer!, forMode: .common)
    }

    private func reconcileCalendarBlocks(
        with events: [CalendarEventSnapshot],
        now: Date
    ) async {
        guard calendarService.hasFullAccess, let vault else { return }
        let startedBlockIDs = Set(
            state.focusSessions.values.compactMap(\.approvedBlockID)
                + focus.runningSessions.compactMap { $0.record.approvedBlockID }
        )
        var changed = false

        for block in state.approvedBlocks.values where block.end > now {
            guard let reference = block.calendarEventReference,
                  !startedBlockIDs.contains(block.id) else { continue }
            guard let event = calendarService.resolve(reference: reference, in: events) else {
                do {
                    try await vault.append(.deleteApprovedBlock(block.id))
                    changed = true
                } catch {
                    errorMessage = "Could not remove a deleted Calendar event: \(error.localizedDescription)"
                    return
                }
                continue
            }

            var updated = block
            updated.title = event.title
            updated.start = event.start
            updated.end = event.end
            updated.activeMinutes = max(1, Int(event.end.timeIntervalSince(event.start) / 60))
            updated.calendarEventReference = event.reference
            if updated != block {
                do {
                    try await vault.append(.upsertApprovedBlock(updated))
                    changed = true
                } catch {
                    errorMessage = "Could not synchronize a Calendar event: \(error.localizedDescription)"
                    return
                }
            }
        }

        if changed {
            state = await vault.currentState()
            writeWidgetProjection()
        }
    }

    @discardableResult
    private func perform(_ operation: @escaping () async throws -> Void) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func writeWidgetProjection() {
        let tasks = state.tasks.values.sorted { $0.updatedAt > $1.updatedAt }
        let runningTasks = focus.runningSessions.map { session in
            WidgetRunningTask(
                id: session.id,
                title: session.record.title,
                projectedEnd: focus.projectedEnd(for: session.id),
                isPaused: session.isPaused
            )
        }
        let firstRunning = runningTasks.first
        let projection = WidgetProjection(
            currentTitle: firstRunning?.title ?? currentApprovedBlock?.title,
            currentEnd: firstRunning?.projectedEnd ?? currentApprovedBlock?.end,
            completedCount: tasks.filter(\.isCompleted).count,
            totalCount: tasks.count,
            tasks: tasks.prefix(8).map { .init(id: $0.id, title: $0.title, isCompleted: $0.isCompleted) },
            hideTitles: hideWidgetTitles,
            runningTasks: runningTasks
        )
        do {
            try WidgetProjectionStore.write(projection)
            widgetLastUpdated = projection.generatedAt
            widgetSyncStatus = "Widget data is synchronized."
            WidgetCenter.shared.reloadTimelines(ofKind: "FocusPilotWidget")
        } catch {
            widgetLastUpdated = nil
            widgetSyncStatus = error.localizedDescription
        }
    }
}
