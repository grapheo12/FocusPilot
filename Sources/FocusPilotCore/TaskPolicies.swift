import Foundation

public enum WorkingWeek {
    public static func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday - Weekday.monday.rawValue + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -daysSinceMonday, to: day),
              let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }
}

public enum TaskRetentionPolicy {
    public static func completionDate(for task: TaskItem) -> Date? {
        guard task.isCompleted else { return nil }
        return task.completedAt ?? task.updatedAt
    }

    public static func shouldDelete(
        _ task: TaskItem,
        hasWeeklyCommitment: Bool,
        at date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard !hasWeeklyCommitment,
              let completedAt = completionDate(for: task) else {
            return false
        }
        return completedAt < calendar.startOfDay(for: date)
    }

    public static func nextCleanupDate(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }
}
