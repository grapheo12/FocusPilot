import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @State private var quickTask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.vaultReady {
                Label("Open FocusPilot to configure your vault", systemImage: "lock.doc")
                    .foregroundStyle(.secondary)
            } else if let title = model.focus.title {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.focus.phase == .breakTime ? "Break" : "Current task")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(title).font(.headline).lineLimit(2)
                    }
                    Spacer()
                    Text(model.focus.displayTime)
                        .font(.title2.monospacedDigit())
                }
                HStack {
                    Button(model.focus.phase == .paused ? "Resume" : "Pause") {
                        model.focus.togglePause()
                    }
                    Button("Stop", role: .destructive) { model.focus.stop() }
                }
            } else if let block = model.currentApprovedBlock ?? model.nextApprovedBlock {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.currentApprovedBlock == nil ? "Next" : "Now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(block.title).font(.headline)
                    Text(block.start, style: .time).font(.caption)
                }
                Button("Start Focus") { model.startCurrentBlock() }
            } else {
                ContentUnavailableView("Nothing scheduled", systemImage: "checkmark.circle")
                    .frame(height: 90)
            }

            Divider()
            HStack {
                TextField("Add a task", text: $quickTask)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button(action: addTask) { Image(systemName: "plus") }
                    .disabled(quickTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !model.incompleteTasks.isEmpty {
                Divider()
                ForEach(model.incompleteTasks.prefix(4)) { task in
                    HStack {
                        Button {
                            Task { await model.toggleTask(task) }
                        } label: {
                            Image(systemName: "circle")
                        }
                        .buttonStyle(.plain)
                        Text(task.title).lineLimit(1)
                        Spacer()
                        Button { model.start(task) } label: { Image(systemName: "play.fill") }
                            .buttonStyle(.borderless)
                    }
                }
            }

            Divider()
            HStack {
                Button("Open FocusPilot") { NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
    }

    private func addTask() {
        let value = quickTask
        quickTask = ""
        Task { await model.addTask(title: value) }
    }
}
