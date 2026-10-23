import Foundation

public enum Weekday: Int, Codable, CaseIterable, Hashable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    public var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

public enum TaskPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum RecurrenceRule: Codable, Hashable, Sendable {
    case none
    case daily
    case weekdays(Set<Weekday>)
}

public struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var parentID: UUID?
    public var title: String
    public var notes: String
    public var isCompleted: Bool
    public var priority: TaskPriority
    public var estimatedMinutes: Int
    public var earliestStart: Date?
    public var deadline: Date?
    public var recurrence: RecurrenceRule
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        title: String,
        notes: String = "",
        isCompleted: Bool = false,
        priority: TaskPriority = .normal,
        estimatedMinutes: Int = 30,
        earliestStart: Date? = nil,
        deadline: Date? = nil,
        recurrence: RecurrenceRule = .none,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.priority = priority
        self.estimatedMinutes = max(1, estimatedMinutes)
        self.earliestStart = earliestStart
        self.deadline = deadline
        self.recurrence = recurrence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

public struct WeeklyCommitment: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var targetMinutes: Int
    public var minimumBlockMinutes: Int

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        targetMinutes: Int,
        minimumBlockMinutes: Int = 30
    ) {
        self.id = id
        self.taskID = taskID
        self.targetMinutes = max(1, targetMinutes)
        self.minimumBlockMinutes = max(15, minimumBlockMinutes)
    }
}

public struct DailyWorkingHours: Codable, Hashable, Sendable {
    public var weekday: Weekday
    public var startMinute: Int
    public var endMinute: Int
    public var isEnabled: Bool

    public init(weekday: Weekday, startMinute: Int, endMinute: Int, isEnabled: Bool) {
        self.weekday = weekday
        self.startMinute = min(max(0, startMinute), 1439)
        self.endMinute = min(max(1, endMinute), 1440)
        self.isEnabled = isEnabled
    }
}

public enum PlannedBlockKind: String, Codable, Sendable {
    case task
    case deepThinking
    case calendarEvent
}

public struct CalendarEventReference: Codable, Hashable, Sendable {
    public var calendarIdentifier: String
    public var eventIdentifier: String?
    public var externalIdentifier: String?
    public var occurrenceStart: Date

    public init(
        calendarIdentifier: String,
        eventIdentifier: String?,
        externalIdentifier: String?,
        occurrenceStart: Date
    ) {
        self.calendarIdentifier = calendarIdentifier
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.occurrenceStart = occurrenceStart
    }
}

public struct ProposedBlock: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID?
    public var title: String
    public var start: Date
    public var end: Date
    public var activeMinutes: Int
    public var kind: PlannedBlockKind
    public var calendarEventReference: CalendarEventReference?

    public init(
        id: UUID = UUID(),
        taskID: UUID?,
        title: String,
        start: Date,
        end: Date,
        activeMinutes: Int,
        kind: PlannedBlockKind,
        calendarEventReference: CalendarEventReference? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.start = start
        self.end = end
        self.activeMinutes = activeMinutes
        self.kind = kind
        self.calendarEventReference = calendarEventReference
    }
}

public struct ApprovedBlock: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID?
    public var title: String
    public var start: Date
    public var end: Date
    public var activeMinutes: Int
    public var kind: PlannedBlockKind
    public var hasCalendarConflict: Bool
    public var calendarEventReference: CalendarEventReference?

    public init(
        id: UUID = UUID(),
        taskID: UUID?,
        title: String,
        start: Date,
        end: Date,
        activeMinutes: Int,
        kind: PlannedBlockKind,
        hasCalendarConflict: Bool = false,
        calendarEventReference: CalendarEventReference? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.start = start
        self.end = end
        self.activeMinutes = activeMinutes
        self.kind = kind
        self.hasCalendarConflict = hasCalendarConflict
        self.calendarEventReference = calendarEventReference
    }

    public init(proposal: ProposedBlock) {
        self.init(
            taskID: proposal.taskID,
            title: proposal.title,
            start: proposal.start,
            end: proposal.end,
            activeMinutes: proposal.activeMinutes,
            kind: proposal.kind,
            calendarEventReference: proposal.calendarEventReference
        )
    }
}

public struct FocusSession: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID?
    public var approvedBlockID: UUID?
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var activeSeconds: Int

    public init(
        id: UUID = UUID(),
        taskID: UUID?,
        approvedBlockID: UUID? = nil,
        title: String,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        activeSeconds: Int = 0
    ) {
        self.id = id
        self.taskID = taskID
        self.approvedBlockID = approvedBlockID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = activeSeconds
    }
}

public struct CompletionRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var completedAt: Date
    public var activeMinutes: Int

    public init(id: UUID = UUID(), taskID: UUID, completedAt: Date = .now, activeMinutes: Int = 0) {
        self.id = id
        self.taskID = taskID
        self.completedAt = completedAt
        self.activeMinutes = max(0, activeMinutes)
    }
}

public struct PlannerSettings: Codable, Hashable, Sendable {
    public var workingHours: [DailyWorkingHours]
    public var planningGranularityMinutes: Int
    public var minimumFlexibleBlockMinutes: Int
    public var deepThinkingMinutes: Int

    public init(
        workingHours: [DailyWorkingHours] = Self.defaultWorkingHours,
        planningGranularityMinutes: Int = 15,
        minimumFlexibleBlockMinutes: Int = 30,
        deepThinkingMinutes: Int = 120
    ) {
        self.workingHours = workingHours
        self.planningGranularityMinutes = planningGranularityMinutes
        self.minimumFlexibleBlockMinutes = minimumFlexibleBlockMinutes
        self.deepThinkingMinutes = deepThinkingMinutes
    }

    public static let defaultWorkingHours = Weekday.allCases.map {
        DailyWorkingHours(
            weekday: $0,
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            isEnabled: ![Weekday.saturday, .sunday].contains($0)
        )
    }
}

public struct NotificationSettings: Codable, Hashable, Sendable {
    public var nagIntervalMinutes: Int
    public var focusIntervalMinutes: Int
    public var breakMinutes: Int

    public init(nagIntervalMinutes: Int = 15, focusIntervalMinutes: Int = 30, breakMinutes: Int = 5) {
        self.nagIntervalMinutes = max(1, nagIntervalMinutes)
        self.focusIntervalMinutes = max(1, focusIntervalMinutes)
        self.breakMinutes = max(1, breakMinutes)
    }
}

public struct AppState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var tasks: [UUID: TaskItem]
    public var weeklyCommitments: [UUID: WeeklyCommitment]
    public var approvedBlocks: [UUID: ApprovedBlock]
    public var focusSessions: [UUID: FocusSession]
    public var completionRecords: [UUID: CompletionRecord]
    public var plannerSettings: PlannerSettings
    public var notificationSettings: NotificationSettings

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        tasks: [UUID: TaskItem] = [:],
        weeklyCommitments: [UUID: WeeklyCommitment] = [:],
        approvedBlocks: [UUID: ApprovedBlock] = [:],
        focusSessions: [UUID: FocusSession] = [:],
        completionRecords: [UUID: CompletionRecord] = [:],
        plannerSettings: PlannerSettings = .init(),
        notificationSettings: NotificationSettings = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.tasks = tasks
        self.weeklyCommitments = weeklyCommitments
        self.approvedBlocks = approvedBlocks
        self.focusSessions = focusSessions
        self.completionRecords = completionRecords
        self.plannerSettings = plannerSettings
        self.notificationSettings = notificationSettings
    }
}
