import FocusPilotCore
import SwiftUI

struct PlannerView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Seven-day plan").font(.largeTitle.bold())
                Spacer()
                Button("Refresh") { Task { await model.refreshPlan() } }
                Button("Approve All") { Task { await model.approveAll() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.proposals.isEmpty)
            }

            List {
                if !model.state.approvedBlocks.isEmpty {
                    Section("Approved") {
                        ForEach(model.state.approvedBlocks.values.sorted { $0.start < $1.start }) { block in
                            BlockRow(title: block.title, start: block.start, end: block.end, kind: block.kind)
                        }
                    }
                }
                Section("Suggestions") {
                    ForEach(model.proposals) { proposal in
                        HStack {
                            BlockRow(title: proposal.title, start: proposal.start, end: proposal.end, kind: proposal.kind)
                            Spacer()
                            Button("Approve") { Task { await model.approve(proposal) } }
                        }
                    }
                }
                if !model.unscheduledTaskIDs.isEmpty {
                    Section("Could not fit") {
                        ForEach(Array(model.unscheduledTaskIDs), id: \.self) { id in
                            Text(model.state.tasks[id]?.title ?? "Unknown task")
                        }
                    }
                }
            }
            .overlay {
                if model.proposals.isEmpty && model.state.approvedBlocks.isEmpty {
                    ContentUnavailableView("No plan yet", systemImage: "calendar.badge.clock", description: Text("Add tasks, then refresh the planner."))
                }
            }
        }
        .task { await model.refreshPlan() }
    }
}

private struct BlockRow: View {
    let title: String
    let start: Date
    let end: Date
    let kind: PlannedBlockKind

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind == .deepThinking ? "brain.head.profile" : "checkmark.square")
                .foregroundStyle(kind == .deepThinking ? .purple : .blue)
            VStack(alignment: .leading) {
                Text(title)
                Text("\(start.formatted(date: .abbreviated, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
