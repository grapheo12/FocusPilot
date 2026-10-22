import Foundation

public enum WidgetProjectionStoreError: LocalizedError, Equatable {
    case sharedContainerUnavailable

    public var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            "Widget sharing is unavailable. Build both targets with the same Apple Developer team and App Group."
        }
    }
}

public enum WidgetProjectionStore {
    public static let defaultAppGroupIdentifier = "group.com.focuspilot.shared"
    public static let filename = "widget-projection.json"

    public static func projectionURL(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) throws -> URL {
        let appGroupIdentifier = bundle.object(
            forInfoDictionaryKey: "FocusPilotAppGroupIdentifier"
        ) as? String ?? defaultAppGroupIdentifier
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw WidgetProjectionStoreError.sharedContainerUnavailable
        }
        return container.appending(path: filename)
    }

    public static func write(
        _ projection: WidgetProjection,
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) throws {
        try write(
            projection,
            to: projectionURL(fileManager: fileManager, bundle: bundle),
            fileManager: fileManager
        )
    }

    public static func write(
        _ projection: WidgetProjection,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(projection).write(to: url, options: .atomic)
    }

    public static func read(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) throws -> WidgetProjection {
        try read(from: projectionURL(fileManager: fileManager, bundle: bundle))
    }

    public static func read(from url: URL) throws -> WidgetProjection {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(WidgetProjection.self, from: Data(contentsOf: url))
    }
}

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

public struct WidgetRunningTask: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var projectedEnd: Date?
    public var isPaused: Bool

    public init(id: UUID, title: String, projectedEnd: Date?, isPaused: Bool) {
        self.id = id
        self.title = title
        self.projectedEnd = projectedEnd
        self.isPaused = isPaused
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
    public var runningTasks: [WidgetRunningTask]?

    public init(
        generatedAt: Date = .now,
        currentTitle: String?,
        currentEnd: Date?,
        completedCount: Int,
        totalCount: Int,
        tasks: [WidgetTask],
        hideTitles: Bool,
        runningTasks: [WidgetRunningTask]? = nil
    ) {
        self.generatedAt = generatedAt
        self.currentTitle = currentTitle
        self.currentEnd = currentEnd
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.tasks = tasks
        self.hideTitles = hideTitles
        self.runningTasks = runningTasks
    }
}
