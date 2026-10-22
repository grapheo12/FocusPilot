import AppKit
import Foundation
import FocusPilotCore
import FocusPilotPlanner
import FocusPilotVault
import ServiceManagement

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
    @Published var lastCompactionMessage: String?
    @Published var startAtLogin = SMAppService.mainApp.status == .enabled

    let calendarService = CalendarService()
    let focus = FocusController()

    private var vault: VaultStore?
    private var vaultKey: Data?
    private let defaults = UserDefaults.standard

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

    var currentApprovedBlock: ApprovedBlock? {
        let now = Date.now
        return state.approvedBlocks.values
            .filter { $0.start <= now && $0.end > now }
            .sorted { $0.start < $1.start }
            .first
    }

    var nextApprovedBlock: ApprovedBlock? {
        state.approvedBlocks.values.filter { $0.start > .now }.sorted { $0.start < $1.start }.first
    }

    var menuTitle: String {
        if let title = focus.title { return "\(title) · \(focus.displayTime)" }
        if let block = currentApprovedBlock { return block.title }
        return nextApprovedBlock.map { "Next: \($0.title)" } ?? "FocusPilot"
    }

    init() {
        focus.onSessionChanged = { [weak self] session in
            self?.persistSession(session)
        }
        Task { await restoreVaultIfPossible() }
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
            self.writeWidgetProjection()
        }
    }

    func addTask(title: String, parentID: UUID? = nil) async {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        await mutate(.upsertTask(TaskItem(parentID: parentID, title: clean)))
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
        await mutate(.upsertTask(changed))
        if changed.isCompleted {
            await mutate(.addCompletionRecord(.init(taskID: changed.id)))
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
        await mutate(.upsertApprovedBlock(.init(proposal: proposal)))
        proposals.removeAll { $0.id == proposal.id }
    }

    func approveAll() async {
        let pending = proposals
        for proposal in pending { await approve(proposal) }
    }

    func start(_ task: TaskItem) {
        focus.settings = state.notificationSettings
        focus.start(taskID: task.id, title: task.title, activeMinutes: task.estimatedMinutes)
        writeWidgetProjection()
    }

    func startCurrentBlock() {
        guard let block = currentApprovedBlock ?? nextApprovedBlock else { return }
        focus.settings = state.notificationSettings
        focus.start(taskID: block.taskID, title: block.title, activeMinutes: block.activeMinutes)
        writeWidgetProjection()
    }

    func refreshPlan() async {
        guard vaultReady else { return }
        let end = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        let busy = calendarService.busyIntervals(from: .now, to: end)
        let result = TaskPlanner().generate(.init(
            tasks: Array(state.tasks.values),
            commitments: Array(state.weeklyCommitments.values),
            approvedBlocks: Array(state.approvedBlocks.values),
            completionRecords: Array(state.completionRecords.values),
            busyIntervals: busy,
            settings: state.plannerSettings,
            notificationSettings: state.notificationSettings
        ))
        proposals = result.proposals
        unscheduledTaskIDs = result.unscheduledTaskIDs
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

    private func mutate(_ mutation: VaultMutation) async {
        await perform {
            guard let vault = self.vault else { return }
            try await vault.append(mutation)
            self.state = await vault.currentState()
            self.writeWidgetProjection()
            await self.refreshPlan()
        }
    }

    private func persistSession(_ session: FocusSession) {
        Task {
            await mutate(.upsertFocusSession(session))
            if let taskID = session.taskID {
                await mutate(.addCompletionRecord(.init(taskID: taskID, activeMinutes: session.activeSeconds / 60)))
            }
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func writeWidgetProjection() {
        let tasks = state.tasks.values.sorted { $0.updatedAt > $1.updatedAt }
        let projection = WidgetProjection(
            currentTitle: focus.title ?? currentApprovedBlock?.title,
            currentEnd: currentApprovedBlock?.end,
            completedCount: tasks.filter(\.isCompleted).count,
            totalCount: tasks.count,
            tasks: tasks.prefix(8).map { .init(id: $0.id, title: $0.title, isCompleted: $0.isCompleted) },
            hideTitles: hideWidgetTitles
        )
        guard let url = widgetProjectionURL() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.vaultEncoder.encode(projection).write(to: url, options: .atomic)
    }

    private func widgetProjectionURL() -> URL? {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.focuspilot.shared") {
            return group.appending(path: "widget-projection.json")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "FocusPilot/widget-projection.json")
    }
}
