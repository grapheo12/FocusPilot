import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppModel
    @State private var quickTask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.vaultReady {
                Label("Open FocusPilot to configure your vault", systemImage: "lock.doc")
                    .foregroundStyle(.secondary)
            } else if !model.focus.runningSessions.isEmpty {
                if model.focus.phase == .breakTime {
                    HStack {
                        Label("Shared break", systemImage: "cup.and.saucer.fill")
                        Spacer()
                        Text(model.focus.sharedBreakDisplayTime)
                            .monospacedDigit()
                    }
                }
                ForEach(model.focus.runningSessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(session.record.title).font(.headline).lineLimit(1)
                            Spacer()
                            Text(model.focus.phase == .breakTime ? "Break" : session.displayTime)
                                .monospacedDigit()
                        }
                        HStack {
                            Button(session.isPaused ? "Resume" : "Pause") {
                                model.toggleFocusPause(sessionID: session.id)
                            }
                            Button("Stop", role: .destructive) {
                                model.stopFocus(sessionID: session.id)
                            }
                        }
                    }
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
                    }
                }
            }

            Divider()
            HStack {
                Button("Open FocusPilot") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
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
