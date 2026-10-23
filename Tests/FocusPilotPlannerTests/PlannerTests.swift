import Foundation
import Testing
import FocusPilotCore
@testable import FocusPilotPlanner

private func fixedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

@Test func activeMinutesFitEditedWallClockRange() {
    let settings = NotificationSettings(
        nagIntervalMinutes: 15,
        focusIntervalMinutes: 30,
        breakMinutes: 5
    )

    #expect(FocusTiming.wallMinutes(for: 60, settings: settings) == 65)
    #expect(FocusTiming.activeMinutes(fittingWallMinutes: 65, settings: settings) == 60)
    #expect(FocusTiming.activeMinutes(fittingWallMinutes: 64, settings: settings) == 59)
}

@Test func weeklyProgressUsesMondayThroughSunday() throws {
    let calendar = fixedCalendar()
    let taskID = UUID()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12)))
    let previousSunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12)))
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
    let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)))
    let nextMonday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12)))
    let records = [
        CompletionRecord(taskID: taskID, completedAt: previousSunday, activeMinutes: 10),
        CompletionRecord(taskID: taskID, completedAt: monday, activeMinutes: 20),
        CompletionRecord(taskID: taskID, completedAt: sunday, activeMinutes: 30),
        CompletionRecord(taskID: taskID, completedAt: nextMonday, activeMinutes: 40)
    ]

    let minutes = WeeklyProgress.completedMinutes(
        taskID: taskID,
        containing: now,
        records: records,
        calendar: calendar
    )

    #expect(minutes == 50)
}

@Test func weeklyProgressIncludesRunningFocusTime() throws {
    let calendar = fixedCalendar()
    let taskID = UUID()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12)))
    let completed = CompletionRecord(taskID: taskID, completedAt: now, activeMinutes: 30)
    let running = FocusSession(
        taskID: taskID,
        title: "Weekly project",
        startedAt: now.addingTimeInterval(-120),
        activeSeconds: 60
    )

    let minutes = WeeklyProgress.focusedMinutes(
        taskID: taskID,
        containing: now,
        records: [completed],
        runningSessions: [running],
        calendar: calendar
    )

    #expect(minutes == 31)
}

@Test func metWeeklyCommitmentDoesNotGenerateMoreTaskTime() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 8)))
    let task = TaskItem(title: "Weekly project", estimatedMinutes: 30)
    let commitment = WeeklyCommitment(taskID: task.id, targetMinutes: 120)
    let completed = CompletionRecord(taskID: task.id, completedAt: now, activeMinutes: 120)

    let result = TaskPlanner().generate(.init(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [task],
        commitments: [commitment],
        approvedBlocks: [],
        completionRecords: [completed],
        busyIntervals: [],
        settings: .init(),
        notificationSettings: .init()
    ))

    #expect(!result.proposals.contains { $0.taskID == task.id })
    #expect(!result.unscheduledTaskIDs.contains(task.id))
}

@Test func proposesDeepThinkingBeforeFlexibleTasks() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let task = TaskItem(title: "Flexible", estimatedMinutes: 60)
    let request = PlanRequest(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [task],
        commitments: [],
        approvedBlocks: [],
        completionRecords: [],
        busyIntervals: [],
        settings: .init(),
        notificationSettings: .init()
    )

    let result = TaskPlanner().generate(request)

    #expect(result.proposals.contains { $0.kind == .deepThinking })
    #expect(result.proposals.contains { $0.taskID == task.id })
}

@Test func proposesEveryNonOverlappingTwoHourSlot() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let settings = PlannerSettings(workingHours: [
        DailyWorkingHours(weekday: .monday, startMinute: 9 * 60, endMinute: 13 * 60, isEnabled: true)
    ])

    let result = TaskPlanner().generate(.init(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [],
        commitments: [],
        approvedBlocks: [],
        completionRecords: [],
        busyIntervals: [],
        settings: settings,
        notificationSettings: .init()
    ))
    let deepBlocks = result.proposals.filter { $0.kind == .deepThinking }

    #expect(deepBlocks.count == 2)
    #expect(calendar.component(.hour, from: deepBlocks[0].start) == 9)
    #expect(calendar.component(.hour, from: deepBlocks[1].start) == 11)
    #expect(deepBlocks.allSatisfy { Int($0.end.timeIntervalSince($0.start) / 60) == 120 })
    #expect(deepBlocks.allSatisfy { $0.activeMinutes == 105 })
}

@Test func proposesSlotsInEverySeparateFreeInterval() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let busyStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 11)))
    let busyEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))

    let result = TaskPlanner().generate(.init(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [],
        commitments: [],
        approvedBlocks: [],
        completionRecords: [],
        busyIntervals: [.init(start: busyStart, end: busyEnd)],
        settings: .init(),
        notificationSettings: .init()
    ))
    let starts = result.proposals
        .filter { $0.kind == .deepThinking }
        .map { calendar.component(.hour, from: $0.start) }

    #expect(starts == [9, 12, 14])
}

@Test func roundsTodaysDeepThinkingStartUpToPlanningGranularity() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 10,
        day: 19,
        hour: 9,
        minute: 7
    )))
    let settings = PlannerSettings(workingHours: [
        DailyWorkingHours(weekday: .monday, startMinute: 9 * 60, endMinute: 12 * 60, isEnabled: true)
    ])

    let result = TaskPlanner().generate(.init(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [],
        commitments: [],
        approvedBlocks: [],
        completionRecords: [],
        busyIntervals: [],
        settings: settings,
        notificationSettings: .init()
    ))
    let block = try #require(result.proposals.first { $0.kind == .deepThinking })

    #expect(calendar.component(.hour, from: block.start) == 9)
    #expect(calendar.component(.minute, from: block.start) == 15)
    #expect(calendar.component(.hour, from: block.end) == 11)
    #expect(calendar.component(.minute, from: block.end) == 15)
}

@Test func deepThinkingChoicesDoNotReserveTaskTime() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let task = TaskItem(title: "Flexible", estimatedMinutes: 60)
    let settings = PlannerSettings(workingHours: [
        DailyWorkingHours(weekday: .monday, startMinute: 9 * 60, endMinute: 13 * 60, isEnabled: true)
    ])

    let result = TaskPlanner().generate(.init(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [task],
        commitments: [],
        approvedBlocks: [],
        completionRecords: [],
        busyIntervals: [],
        settings: settings,
        notificationSettings: .init()
    ))
    let deepBlock = try #require(result.proposals.first { $0.kind == .deepThinking })
    let taskBlock = try #require(result.proposals.first { $0.taskID == task.id })

    #expect(taskBlock.start < deepBlock.end)
    #expect(taskBlock.end > deepBlock.start)
}

@Test func plannerAvoidsCalendarBusyTime() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let busyStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9)))
    let busyEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
    let task = TaskItem(title: "Task", estimatedMinutes: 60)
    let request = PlanRequest(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [task],
        commitments: [],
        approvedBlocks: [],
        completionRecords: [],
        busyIntervals: [.init(start: busyStart, end: busyEnd)],
        settings: .init(),
        notificationSettings: .init()
    )

    let result = TaskPlanner().generate(request)

    #expect(result.proposals.allSatisfy { $0.end <= busyStart || $0.start >= busyEnd })
}

@Test func sixtyActiveMinutesIncludeOneBreak() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let task = TaskItem(title: "Task", priority: .urgent, estimatedMinutes: 60)
    let result = TaskPlanner().generate(.init(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [task],
        commitments: [],
        approvedBlocks: [],
        completionRecords: [],
        busyIntervals: [],
        settings: .init(),
        notificationSettings: .init()
    ))

    let block = try #require(result.proposals.first { $0.taskID == task.id })
    #expect(Int(block.end.timeIntervalSince(block.start) / 60) == 65)
}

@Test func approvedTaskMinutesAreNotProposedAgain() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 13)))
    let task = TaskItem(title: "Approved", estimatedMinutes: 60)
    let approved = ApprovedBlock(
        taskID: task.id,
        title: task.title,
        start: start,
        end: start.addingTimeInterval(65 * 60),
        activeMinutes: 60,
        kind: .task
    )

    let result = TaskPlanner().generate(.init(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [task],
        commitments: [],
        approvedBlocks: [approved],
        completionRecords: [],
        busyIntervals: [],
        settings: .init(),
        notificationSettings: .init()
    ))

    #expect(!result.proposals.contains { $0.taskID == task.id })
}

@Test func recurringApprovedBlockOnlySuppressesItsDay() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 13)))
    let task = TaskItem(title: "Daily", estimatedMinutes: 30, recurrence: .daily)
    let approved = ApprovedBlock(
        taskID: task.id,
        title: task.title,
        start: start,
        end: start.addingTimeInterval(30 * 60),
        activeMinutes: 30,
        kind: .task
    )

    let result = TaskPlanner().generate(.init(
        now: now,
        days: 2,
        calendar: calendar,
        tasks: [task],
        commitments: [],
        approvedBlocks: [approved],
        completionRecords: [],
        busyIntervals: [],
        settings: .init(),
        notificationSettings: .init()
    ))

    let taskProposals = result.proposals.filter { $0.taskID == task.id }
    #expect(taskProposals.count == 1)
    #expect(!calendar.isDate(taskProposals[0].start, inSameDayAs: start))
}

@Test func approvedDeepThinkingBlockIsNotDuplicated() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9)))
    let approved = ApprovedBlock(
        taskID: nil,
        title: "Deep thinking",
        start: start,
        end: start.addingTimeInterval(130 * 60),
        activeMinutes: 120,
        kind: .deepThinking
    )

    let result = TaskPlanner().generate(.init(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [],
        commitments: [],
        approvedBlocks: [approved],
        completionRecords: [],
        busyIntervals: [],
        settings: .init(),
        notificationSettings: .init()
    ))

    #expect(!result.proposals.contains { $0.kind == .deepThinking })
}
