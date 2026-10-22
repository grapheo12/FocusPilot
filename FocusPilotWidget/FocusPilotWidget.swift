import FocusPilotCore
import SwiftUI
import WidgetKit

struct FocusPilotEntry: TimelineEntry {
    let date: Date
    let projection: WidgetProjection
}

struct FocusPilotProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusPilotEntry {
        FocusPilotEntry(date: .now, projection: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusPilotEntry) -> Void) {
        let fallback: WidgetProjection = context.isPreview ? .preview : .empty
        completion(FocusPilotEntry(date: .now, projection: loadProjection() ?? fallback))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusPilotEntry>) -> Void) {
        let entry = FocusPilotEntry(date: .now, projection: loadProjection() ?? .empty)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60))))
    }

    private func loadProjection() -> WidgetProjection? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.focuspilot.shared") else {
            return nil
        }
        let url = container.appending(path: "widget-projection.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetProjection.self, from: data)
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

            if let current = entry.projection.currentTitle {
                Text(entry.projection.hideTitles ? "Current task" : current)
                    .font(.title3.bold())
                    .lineLimit(2)
                if let end = entry.projection.currentEnd {
                    Text(timerInterval: Date.now...end, countsDown: true)
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
