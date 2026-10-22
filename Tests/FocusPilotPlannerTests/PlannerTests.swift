import Foundation
import Testing
import FocusPilotCore
@testable import FocusPilotPlanner

private func fixedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
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

    #expect(result.proposals.first?.kind == .deepThinking)
    #expect(result.proposals.contains { $0.taskID == task.id })
}

@Test func plannerAvoidsCalendarBusyTime() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let busyStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9)))
    let busyEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
    let task = TaskItem(title: "Task", estimatedMinutes: 60)
    var settings = PlannerSettings()
    settings.deepThinkingMinutes = 120
    let request = PlanRequest(
        now: now,
        days: 1,
        calendar: calendar,
        tasks: [task],
        commitments: [],
        approvedBlocks: [],
        completionRecords: [],
        busyIntervals: [.init(start: busyStart, end: busyEnd)],
        settings: settings,
        notificationSettings: .init()
    )

    let result = TaskPlanner().generate(request)

    #expect(result.proposals.allSatisfy { $0.end <= busyStart || $0.start >= busyEnd })
}

@Test func sixtyActiveMinutesIncludeOneBreak() throws {
    let calendar = fixedCalendar()
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)))
    let task = TaskItem(title: "Task", priority: .urgent, estimatedMinutes: 60)
    var settings = PlannerSettings()
    settings.deepThinkingMinutes = 600
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
