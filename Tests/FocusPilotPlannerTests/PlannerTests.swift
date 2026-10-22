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
