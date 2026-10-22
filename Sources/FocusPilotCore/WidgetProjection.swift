import Foundation

public struct WidgetTask: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool

    public init(id: UUID, title: String, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

public struct WidgetProjection: Codable, Hashable, Sendable {
    public var generatedAt: Date
    public var currentTitle: String?
    public var currentEnd: Date?
    public var completedCount: Int
    public var totalCount: Int
    public var tasks: [WidgetTask]
    public var hideTitles: Bool

    public init(
        generatedAt: Date = .now,
        currentTitle: String?,
        currentEnd: Date?,
        completedCount: Int,
        totalCount: Int,
        tasks: [WidgetTask],
        hideTitles: Bool
    ) {
        self.generatedAt = generatedAt
        self.currentTitle = currentTitle
        self.currentEnd = currentEnd
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.tasks = tasks
        self.hideTitles = hideTitles
    }
}
