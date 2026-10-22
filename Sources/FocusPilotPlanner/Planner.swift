import Foundation
import FocusPilotCore

public struct BusyInterval: Hashable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public enum FocusTiming {
    public static func wallMinutes(for activeMinutes: Int, settings: NotificationSettings) -> Int {
        guard activeMinutes > 0 else { return 0 }
        let completedIntervalsBeforeEnd = (activeMinutes - 1) / settings.focusIntervalMinutes
        return activeMinutes + completedIntervalsBeforeEnd * settings.breakMinutes
    }

    public static func activeMinutes(fittingWallMinutes wallMinutes: Int, settings: NotificationSettings) -> Int {
        guard wallMinutes > 0 else { return 0 }
        return (1...wallMinutes).reversed().first {
            self.wallMinutes(for: $0, settings: settings) <= wallMinutes
        } ?? 0
    }
}

public struct PlanRequest: Sendable {
    public var now: Date
    public var days: Int
    public var calendar: Calendar
    public var tasks: [TaskItem]
    public var commitments: [WeeklyCommitment]
    public var approvedBlocks: [ApprovedBlock]
    public var completionRecords: [CompletionRecord]
    public var busyIntervals: [BusyInterval]
    public var settings: PlannerSettings
    public var notificationSettings: NotificationSettings

    public init(
        now: Date = .now,
        days: Int = 7,
        calendar: Calendar = .current,
        tasks: [TaskItem],
        commitments: [WeeklyCommitment],
        approvedBlocks: [ApprovedBlock],
        completionRecords: [CompletionRecord],
        busyIntervals: [BusyInterval],
        settings: PlannerSettings,
        notificationSettings: NotificationSettings
    ) {
        self.now = now
        self.days = max(1, days)
        self.calendar = calendar
        self.tasks = tasks
        self.commitments = commitments
        self.approvedBlocks = approvedBlocks
        self.completionRecords = completionRecords
        self.busyIntervals = busyIntervals
        self.settings = settings
        self.notificationSettings = notificationSettings
    }
}

public struct PlanResult: Sendable {
    public var proposals: [ProposedBlock]
    public var unscheduledTaskIDs: Set<UUID>

    public init(proposals: [ProposedBlock], unscheduledTaskIDs: Set<UUID>) {
        self.proposals = proposals
        self.unscheduledTaskIDs = unscheduledTaskIDs
    }
}

public enum WeeklyProgress {
    public static func completedMinutes(
        taskID: UUID,
        containing date: Date,
        records: [CompletionRecord],
        calendar: Calendar
    ) -> Int {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return records
            .filter { $0.taskID == taskID && interval.contains($0.completedAt) }
            .reduce(0) { $0 + $1.activeMinutes }
    }
}

public struct TaskPlanner: Sendable {
    public init() {}

    public func generate(_ request: PlanRequest) -> PlanResult {
        let calendar = request.calendar
        let startDay = calendar.startOfDay(for: request.now)
        let taskLookup = Dictionary(uniqueKeysWithValues: request.tasks.map { ($0.id, $0) })
        let occupied = request.busyIntervals + request.approvedBlocks.map {
            BusyInterval(start: $0.start, end: $0.end)
        }
        var proposals: [ProposedBlock] = []
        var remaining = initialDemand(request: request)

        for dayOffset in 0..<request.days {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startDay),
                  let workWindow = workingWindow(on: day, request: request) else { continue }

            for task in request.tasks where isRecurring(task) {
                let approvedMinutes = approvedMinutes(for: task.id, on: day, request: request)
                remaining[task.id] = max(0, task.estimatedMinutes - approvedMinutes)
            }

            var free = subtract(occupied: occupied, from: workWindow)
            if dayOffset == 0 {
                free = trim(intervals: free, after: request.now)
            }

            proposals.append(contentsOf: deepThinkingBlocks(on: day, in: free, request: request))

            let eligible = request.tasks
                .filter { isEligible($0, on: day, calendar: calendar) }
                .filter { !$0.isCompleted && remaining[$0.id, default: 0] > 0 }
                .sorted(by: taskOrdering)

            for task in eligible {
                guard var activeMinutes = remaining[task.id], activeMinutes > 0 else { continue }
                let minimum = request.commitments.first(where: { $0.taskID == task.id })?.minimumBlockMinutes
                    ?? request.settings.minimumFlexibleBlockMinutes

                while activeMinutes > 0 {
                    let preferred = min(activeMinutes, 120)
                    guard let allocation = allocate(
                        preferredActiveMinutes: preferred,
                        minimumActiveMinutes: min(minimum, activeMinutes),
                        free: free,
                        notificationSettings: request.notificationSettings,
                        granularity: request.settings.planningGranularityMinutes
                    ) else { break }

                    let block = ProposedBlock(
                        taskID: task.id,
                        title: task.title,
                        start: allocation.interval.start,
                        end: allocation.interval.end,
                        activeMinutes: allocation.activeMinutes,
                        kind: .task
                    )
                    proposals.append(block)
                    activeMinutes -= allocation.activeMinutes
                    remaining[task.id] = activeMinutes
                    free = subtract(occupied: [allocation.interval], from: free)
                }
            }

        }

        let unscheduled = Set(remaining.filter { $0.value > 0 }.map(\.key)).intersection(taskLookup.keys)
        return PlanResult(
            proposals: proposals.sorted { $0.start < $1.start },
            unscheduledTaskIDs: unscheduled
        )
    }

    private func initialDemand(request: PlanRequest) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for task in request.tasks where !task.isCompleted {
            result[task.id] = task.estimatedMinutes
        }

        for commitment in request.commitments {
            let completed = WeeklyProgress.completedMinutes(
                taskID: commitment.taskID,
                containing: request.now,
                records: request.completionRecords,
                calendar: request.calendar
            )
            result[commitment.taskID] = max(result[commitment.taskID, default: 0], commitment.targetMinutes - completed)
        }

        for task in request.tasks where !isRecurring(task) {
            let approved = request.approvedBlocks
                .filter { $0.taskID == task.id && $0.end > request.now }
                .reduce(0) { $0 + $1.activeMinutes }
            result[task.id] = max(0, result[task.id, default: 0] - approved)
        }
        return result
    }

    private func approvedMinutes(for taskID: UUID, on day: Date, request: PlanRequest) -> Int {
        request.approvedBlocks
            .filter { block in
                block.taskID == taskID && request.calendar.isDate(block.start, inSameDayAs: day)
            }
            .reduce(0) { $0 + $1.activeMinutes }
    }

    private func workingWindow(on day: Date, request: PlanRequest) -> BusyInterval? {
        let calendar = request.calendar
        let weekdayValue = calendar.component(.weekday, from: day)
        guard let weekday = Weekday(rawValue: weekdayValue),
              let hours = request.settings.workingHours.first(where: { $0.weekday == weekday }),
              hours.isEnabled,
              hours.endMinute > hours.startMinute,
              let start = calendar.date(byAdding: .minute, value: hours.startMinute, to: calendar.startOfDay(for: day)),
              let end = calendar.date(byAdding: .minute, value: hours.endMinute, to: calendar.startOfDay(for: day)) else {
            return nil
        }
        return BusyInterval(start: start, end: end)
    }

    private func isEligible(_ task: TaskItem, on day: Date, calendar: Calendar) -> Bool {
        if let earliestStart = task.earliestStart,
           calendar.startOfDay(for: day) < calendar.startOfDay(for: earliestStart) {
            return false
        }

        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { return false }
        switch task.recurrence {
        case .none: return true
        case .daily: return true
        case .weekdays(let days): return days.contains(weekday)
        }
    }

    private func isRecurring(_ task: TaskItem) -> Bool {
        if case .none = task.recurrence { return false }
        return true
    }

    private func taskOrdering(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        switch (lhs.deadline, rhs.deadline) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.createdAt < rhs.createdAt
        }
    }

    private func deepThinkingBlocks(
        on day: Date,
        in free: [BusyInterval],
        request: PlanRequest
    ) -> [ProposedBlock] {
        guard !request.approvedBlocks.contains(where: {
            $0.kind == .deepThinking && request.calendar.isDate($0.start, inSameDayAs: day)
        }) else { return [] }

        let wallMinutes = 120
        let activeMinutes = FocusTiming.activeMinutes(
            fittingWallMinutes: wallMinutes,
            settings: request.notificationSettings
        )
        guard activeMinutes > 0 else { return [] }

        return free.flatMap { interval -> [ProposedBlock] in
            var blocks: [ProposedBlock] = []
            var start = roundUp(
                interval.start,
                to: request.settings.planningGranularityMinutes,
                calendar: request.calendar
            )
            var end = start.addingTimeInterval(TimeInterval(wallMinutes * 60))

            while end <= interval.end {
                blocks.append(ProposedBlock(
                    taskID: nil,
                    title: "Deep thinking",
                    start: start,
                    end: end,
                    activeMinutes: activeMinutes,
                    kind: .deepThinking
                ))
                start = end
                end = start.addingTimeInterval(TimeInterval(wallMinutes * 60))
            }
            return blocks
        }
    }

    private func allocate(
        preferredActiveMinutes: Int,
        minimumActiveMinutes: Int,
        free: [BusyInterval],
        notificationSettings: NotificationSettings,
        granularity: Int
    ) -> (interval: BusyInterval, activeMinutes: Int)? {
        for interval in free {
            var candidate = roundDown(preferredActiveMinutes, to: granularity)
            candidate = max(minimumActiveMinutes, candidate)
            while candidate >= minimumActiveMinutes {
                let wall = FocusTiming.wallMinutes(for: candidate, settings: notificationSettings)
                if minutes(in: interval) >= wall {
                    return (
                        BusyInterval(
                            start: interval.start,
                            end: interval.start.addingTimeInterval(TimeInterval(wall * 60))
                        ),
                        candidate
                    )
                }
                candidate -= granularity
            }
        }
        return nil
    }

    private func roundDown(_ value: Int, to granularity: Int) -> Int {
        guard granularity > 0 else { return value }
        return value / granularity * granularity
    }

    private func roundUp(_ date: Date, to granularity: Int, calendar: Calendar) -> Date {
        guard granularity > 0 else { return date }
        let dayStart = calendar.startOfDay(for: date)
        let interval = date.timeIntervalSince(dayStart)
        let step = TimeInterval(granularity * 60)
        let rounded = ceil(interval / step) * step
        return dayStart.addingTimeInterval(rounded)
    }

    private func minutes(in interval: BusyInterval) -> Int {
        max(0, Int(interval.end.timeIntervalSince(interval.start) / 60))
    }

    private func trim(intervals: [BusyInterval], after date: Date) -> [BusyInterval] {
        intervals.compactMap {
            guard $0.end > date else { return nil }
            return BusyInterval(start: max($0.start, date), end: $0.end)
        }
    }

    private func subtract(occupied: [BusyInterval], from source: BusyInterval) -> [BusyInterval] {
        subtract(occupied: occupied, from: [source])
    }

    private func subtract(occupied: [BusyInterval], from sources: [BusyInterval]) -> [BusyInterval] {
        occupied.reduce(sources) { intervals, busy in
            intervals.flatMap { interval -> [BusyInterval] in
                guard busy.start < interval.end, busy.end > interval.start else { return [interval] }
                var parts: [BusyInterval] = []
                if busy.start > interval.start {
                    parts.append(BusyInterval(start: interval.start, end: min(busy.start, interval.end)))
                }
                if busy.end < interval.end {
                    parts.append(BusyInterval(start: max(busy.end, interval.start), end: interval.end))
                }
                return parts.filter { $0.end > $0.start }
            }
        }.sorted { $0.start < $1.start }
    }
}
