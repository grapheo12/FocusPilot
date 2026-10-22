import FocusPilotCore
import SwiftUI
import WidgetKit

struct FocusPilotEntry: TimelineEntry {
    let date: Date
    let projection: WidgetProjection
    let hasSharedData: Bool
}

struct FocusPilotProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusPilotEntry {
        FocusPilotEntry(date: .now, projection: .preview, hasSharedData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusPilotEntry) -> Void) {
        let fallback: WidgetProjection = context.isPreview ? .preview : .empty
        let projection = loadProjection()
        completion(FocusPilotEntry(
            date: .now,
            projection: projection ?? fallback,
            hasSharedData: context.isPreview || projection != nil
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusPilotEntry>) -> Void) {
        let projection = loadProjection()
        let entry = FocusPilotEntry(
            date: .now,
            projection: projection ?? .empty,
            hasSharedData: projection != nil
        )
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60))))
    }

    private func loadProjection() -> WidgetProjection? {
        try? WidgetProjectionStore.read()
    }
}

struct FocusPilotWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusPilotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("FocusPilot", systemImage: "scope")
                    .font(.headline)
                Spacer()
                Text("\(entry.projection.completedCount)/\(entry.projection.totalCount)")
                    .font(.caption.monospacedDigit())
            }

            if !entry.hasSharedData {
                Label("Open FocusPilot to sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            } else if let runningTasks = entry.projection.runningTasks, !runningTasks.isEmpty {
                ForEach(runningTasks.prefix(family == .systemSmall ? 1 : 3)) { task in
                    HStack {
                        Text(entry.projection.hideTitles ? "Active task" : task.title)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Spacer()
                        if task.isPaused {
                            Text("Paused")
                        } else if let end = task.projectedEnd {
                            countdown(to: end)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                }
            } else if let current = entry.projection.currentTitle {
                Text(entry.projection.hideTitles ? "Current task" : current)
                    .font(.title3.bold())
                    .lineLimit(2)
                if let end = entry.projection.currentEnd {
                    countdown(to: end)
                        .font(.caption.monospacedDigit())
                }
            } else {
                Text("Nothing scheduled")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }

            if family != .systemSmall {
                ForEach(entry.projection.tasks.prefix(4)) { task in
                    HStack(spacing: 6) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isCompleted ? .green : .secondary)
                        Text(entry.projection.hideTitles ? "Task" : task.title)
                            .strikethrough(task.isCompleted)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func countdown(to end: Date) -> Text {
        Text(timerInterval: min(Date.now, end)...end, countsDown: true)
    }
}

@main
struct FocusPilotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusPilotWidget", provider: FocusPilotProvider()) { entry in
            FocusPilotWidgetView(entry: entry)
        }
        .configurationDisplayName("FocusPilot Tasks")
        .description("See your current task and daily progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private extension WidgetProjection {
    static let empty = WidgetProjection(
        currentTitle: nil,
        currentEnd: nil,
        completedCount: 0,
        totalCount: 0,
        tasks: [],
        hideTitles: false
    )

    static let preview = WidgetProjection(
        currentTitle: "Write project proposal",
        currentEnd: .now.addingTimeInterval(1800),
        completedCount: 2,
        totalCount: 5,
        tasks: [
            .init(id: UUID(), title: "Write project proposal", isCompleted: false),
            .init(id: UUID(), title: "Review notes", isCompleted: true),
            .init(id: UUID(), title: "Email the team", isCompleted: false)
        ],
        hideTitles: false
    )
}
