import Foundation

public struct LogicalTimestamp: Codable, Hashable, Comparable, Sendable {
    public var milliseconds: Int64
    public var counter: Int

    public init(milliseconds: Int64, counter: Int = 0) {
        self.milliseconds = milliseconds
        self.counter = counter
    }

    public static func < (lhs: LogicalTimestamp, rhs: LogicalTimestamp) -> Bool {
        if lhs.milliseconds != rhs.milliseconds {
            return lhs.milliseconds < rhs.milliseconds
        }
        return lhs.counter < rhs.counter
    }
}

public enum VaultMutation: Codable, Hashable, Sendable {
    case upsertTask(TaskItem)
    case deleteTask(UUID)
    case upsertWeeklyCommitment(WeeklyCommitment)
    case deleteWeeklyCommitment(UUID)
    case upsertApprovedBlock(ApprovedBlock)
    case deleteApprovedBlock(UUID)
    case upsertFocusSession(FocusSession)
    case addCompletionRecord(CompletionRecord)
    case updatePlannerSettings(PlannerSettings)
    case updateNotificationSettings(NotificationSettings)
}

public struct VaultOperation: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID { eventID }
    public var schemaVersion: Int
    public var eventID: UUID
    public var deviceID: UUID
    public var deviceSequence: Int64
    public var timestamp: LogicalTimestamp
    public var mutation: VaultMutation

    public init(
        schemaVersion: Int = 1,
        eventID: UUID = UUID(),
        deviceID: UUID,
        deviceSequence: Int64,
        timestamp: LogicalTimestamp,
        mutation: VaultMutation
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.deviceID = deviceID
        self.deviceSequence = deviceSequence
        self.timestamp = timestamp
        self.mutation = mutation
    }
}

public struct VersionStamp: Comparable, Sendable {
    public var timestamp: LogicalTimestamp
    public var deviceID: UUID

    public static func < (lhs: VersionStamp, rhs: VersionStamp) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.deviceID.uuidString < rhs.deviceID.uuidString
    }
}

public struct ReductionResult: Sendable {
    public var state: AppState
    public var frontier: [UUID: Int64]

    public init(state: AppState, frontier: [UUID: Int64]) {
        self.state = state
        self.frontier = frontier
    }
}

public enum StateReducer {
    public static func reduce(
        base: AppState = .init(),
        frontier baseFrontier: [UUID: Int64] = [:],
        operations: [VaultOperation]
    ) -> ReductionResult {
        var state = base
        var frontier = baseFrontier
        var entityVersions: [String: VersionStamp] = [:]
        var seenEvents = Set<UUID>()

        let sorted = operations.sorted {
            let lhs = VersionStamp(timestamp: $0.timestamp, deviceID: $0.deviceID)
            let rhs = VersionStamp(timestamp: $1.timestamp, deviceID: $1.deviceID)
            if lhs != rhs { return lhs < rhs }
            return $0.eventID.uuidString < $1.eventID.uuidString
        }

        for operation in sorted {
            guard !seenEvents.contains(operation.eventID) else { continue }
            seenEvents.insert(operation.eventID)
            guard operation.deviceSequence > (frontier[operation.deviceID] ?? 0) else { continue }

            let stamp = VersionStamp(timestamp: operation.timestamp, deviceID: operation.deviceID)
            let entityKey = key(for: operation.mutation)
            if let previous = entityVersions[entityKey], stamp < previous {
                continue
            }

            apply(operation.mutation, to: &state)
            entityVersions[entityKey] = stamp
            frontier[operation.deviceID] = max(frontier[operation.deviceID] ?? 0, operation.deviceSequence)
        }

        return ReductionResult(state: state, frontier: frontier)
    }

    private static func key(for mutation: VaultMutation) -> String {
        switch mutation {
        case .upsertTask(let value): "task:\(value.id)"
        case .deleteTask(let id): "task:\(id)"
        case .upsertWeeklyCommitment(let value): "weekly:\(value.id)"
        case .deleteWeeklyCommitment(let id): "weekly:\(id)"
        case .upsertApprovedBlock(let value): "block:\(value.id)"
        case .deleteApprovedBlock(let id): "block:\(id)"
        case .upsertFocusSession(let value): "session:\(value.id)"
        case .addCompletionRecord(let value): "completion:\(value.id)"
        case .updatePlannerSettings: "settings:planner"
        case .updateNotificationSettings: "settings:notifications"
        }
    }

    private static func apply(_ mutation: VaultMutation, to state: inout AppState) {
        switch mutation {
        case .upsertTask(let value): state.tasks[value.id] = value
        case .deleteTask(let id): state.tasks.removeValue(forKey: id)
        case .upsertWeeklyCommitment(let value): state.weeklyCommitments[value.id] = value
        case .deleteWeeklyCommitment(let id): state.weeklyCommitments.removeValue(forKey: id)
        case .upsertApprovedBlock(let value): state.approvedBlocks[value.id] = value
        case .deleteApprovedBlock(let id): state.approvedBlocks.removeValue(forKey: id)
        case .upsertFocusSession(let value): state.focusSessions[value.id] = value
        case .addCompletionRecord(let value): state.completionRecords[value.id] = value
        case .updatePlannerSettings(let value): state.plannerSettings = value
        case .updateNotificationSettings(let value): state.notificationSettings = value
        }
    }
}
