import FocusPilotCore
import SwiftUI

struct TaskListView: View {
    @ObservedObject var model: AppModel
    @State private var newTask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tasks").font(.largeTitle.bold())
                Spacer()
                Text("\(model.incompleteTasks.count) unfinished")
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("What needs doing?", text: $newTask)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
            }
            List {
                ForEach(model.rootTasks) { task in
                    TaskTreeRow(model: model, task: task, depth: 0)
                }
            }
            .overlay {
                if model.rootTasks.isEmpty {
                    ContentUnavailableView("No tasks yet", systemImage: "checklist", description: Text("Add one small, concrete next action."))
                }
            }
        }
    }

    private func add() {
        let value = newTask
        newTask = ""
        Task { await model.addTask(title: value) }
    }
}

private struct TaskTreeRow: View {
    @ObservedObject var model: AppModel
    let task: TaskItem
    let depth: Int
    @State private var isExpanded = true
    @State private var addingChild = false
    @State private var childTitle = ""
    @State private var editing = false

    private var children: [TaskItem] { model.children(of: task.id) }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(children) { child in
                TaskTreeRow(model: model, task: child, depth: depth + 1)
            }
            if addingChild {
                HStack {
                    TextField("Subtask", text: $childTitle)
                        .onSubmit(addChild)
                    Button("Add", action: addChild)
                    Button("Cancel") { addingChild = false }
                }
                .padding(.leading, 18)
            }
        } label: {
            HStack(spacing: 10) {
                Button {
                    Task { await model.toggleTask(task) }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading) {
                    Text(task.title)
                        .strikethrough(task.isCompleted)
                    HStack(spacing: 8) {
                        Text("\(task.estimatedMinutes)m")
                        Text(task.priorityLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button { addingChild = true; isExpanded = true } label: { Image(systemName: "plus") }
                    .help("Add subtask")
                Button { editing = true } label: { Image(systemName: "pencil") }
                    .help("Edit task")
                Button(role: .destructive) {
                    Task { await model.deleteTask(task) }
                } label: { Image(systemName: "trash") }
            }
        }
        .sheet(isPresented: $editing) {
            TaskEditorView(model: model, task: task)
        }
    }

    private func addChild() {
        let value = childTitle
        childTitle = ""
        addingChild = false
        Task { await model.addTask(title: value, parentID: task.id) }
    }
}

private struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var draft: TaskItem
    @State private var weeklyHours: Int
    @State private var hasDeadline: Bool
    @State private var recurrenceChoice: Int

    init(model: AppModel, task: TaskItem) {
        self.model = model
        _draft = State(initialValue: task)
        _weeklyHours = State(initialValue: (model.weeklyCommitment(for: task.id)?.targetMinutes ?? 0) / 60)
        _hasDeadline = State(initialValue: task.deadline != nil)
        let choice: Int
        switch task.recurrence {
        case .none: choice = 0
        case .daily: choice = 1
        case .weekdays: choice = 2
        }
        _recurrenceChoice = State(initialValue: choice)
    }

    var body: some View {
        Form {
            TextField("Title", text: $draft.title)
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(3...8)
            Picker("Priority", selection: $draft.priority) {
                Text("Low").tag(TaskPriority.low)
                Text("Normal").tag(TaskPriority.normal)
                Text("High").tag(TaskPriority.high)
                Text("Urgent").tag(TaskPriority.urgent)
            }
            Stepper("Estimate: \(draft.estimatedMinutes) minutes", value: $draft.estimatedMinutes, in: 5...1440, step: 5)
            Picker("Repeats", selection: $recurrenceChoice) {
                Text("Never").tag(0)
                Text("Daily").tag(1)
                Text("Weekdays").tag(2)
            }
            Toggle("Has deadline", isOn: $hasDeadline)
            if hasDeadline {
                DatePicker("Deadline", selection: Binding(
                    get: { draft.deadline ?? .now },
                    set: { draft.deadline = $0 }
                ))
            }
            Stepper("Weekly commitment: \(weeklyHours) hours", value: $weeklyHours, in: 0...40)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 460)
    }

    private func save() {
        draft.deadline = hasDeadline ? (draft.deadline ?? .now) : nil
        draft.recurrence = switch recurrenceChoice {
        case 1: .daily
        case 2: .weekdays([.monday, .tuesday, .wednesday, .thursday, .friday])
        default: .none
        }
        Task {
            await model.saveTask(draft)
            await model.saveWeeklyCommitment(taskID: draft.id, targetMinutes: weeklyHours * 60)
            dismiss()
        }
    }
}

private extension TaskItem {
    var priorityLabel: String {
        switch priority {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }
}
