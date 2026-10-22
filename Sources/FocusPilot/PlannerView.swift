import AppKit
import FocusPilotCore
import SwiftUI

struct PlannerView: View {
    @ObservedObject var model: AppModel
    @State private var editingBlock: ApprovedBlock?

    private var bulkApprovableProposals: [ProposedBlock] {
        model.proposals.filter { $0.kind == .task }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Seven-day plan").font(.largeTitle.bold())
                Spacer()
                Button("Refresh") { Task { await model.refreshPlan() } }
                Button("Approve All") { Task { await model.approveAll() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(bulkApprovableProposals.isEmpty)
            }

            List {
                if !model.state.approvedBlocks.isEmpty {
                    Section("Approved") {
                        ForEach(model.state.approvedBlocks.values.sorted { $0.start < $1.start }) { block in
                            HStack {
                                BlockRow(
                                    title: block.title,
                                    start: block.start,
                                    end: block.end,
                                    kind: block.kind
                                )
                                Spacer()
                                if let running = model.focus.session(for: block.id) {
                                    Text(model.focus.phase == .breakTime ? "Break" : running.displayTime)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("Start Now") { model.start(block) }
                                }
                                if block.calendarEventReference == nil {
                                    Button("Edit") { editingBlock = block }
                                } else {
                                    Button("Open Calendar") { openCalendar() }
                                }
                            }
                        }
                    }
                }
                Section("Suggestions") {
                    ForEach(model.proposals) { proposal in
                        HStack {
                            BlockRow(
                                title: proposal.title,
                                start: proposal.start,
                                end: proposal.end,
                                kind: proposal.kind
                            )
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
                    ContentUnavailableView(
                        "No plan yet",
                        systemImage: "calendar.badge.clock",
                        description: Text("Add tasks or connect Calendar, then refresh the planner.")
                    )
                }
            }
        }
        .task { await model.refreshPlan() }
        .sheet(item: $editingBlock) { block in
            ApprovedBlockEditor(model: model, block: block)
        }
    }

    private func openCalendar() {
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}

private struct BlockRow: View {
    let title: String
    let start: Date
    let end: Date
    let kind: PlannedBlockKind

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading) {
                Text(title)
                Text(timeRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timeRange: String {
        let endDateStyle: Date.FormatStyle.DateStyle = Calendar.current.isDate(start, inSameDayAs: end)
            ? .omitted
            : .abbreviated
        return "\(start.formatted(date: .abbreviated, time: .shortened))–\(end.formatted(date: endDateStyle, time: .shortened))"
    }

    private var iconName: String {
        switch kind {
        case .task: "checkmark.square"
        case .deepThinking: "brain.head.profile"
        case .calendarEvent: "calendar"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .task: .blue
        case .deepThinking: .purple
        case .calendarEvent: .orange
        }
    }
}

private struct ApprovedBlockEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var draft: ApprovedBlock

    init(model: AppModel, block: ApprovedBlock) {
        self.model = model
        _draft = State(initialValue: block)
    }

    var body: some View {
        Form {
            Text(draft.title).font(.headline)
            DatePicker("Starts", selection: $draft.start)
            DatePicker("Ends", selection: $draft.end)
            if draft.end <= draft.start {
                Text("End time must be after start time.")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    Task {
                        await model.saveApprovedBlock(draft)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.end <= draft.start)
            }
        }
        .padding()
        .frame(width: 440)
    }
}
