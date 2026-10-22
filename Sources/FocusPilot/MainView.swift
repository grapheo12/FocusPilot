import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.vaultReady {
                VStack(spacing: 0) {
                    if model.focus.title != nil {
                        FocusBanner(model: model)
                    }
                    TabView {
                        TaskListView(model: model)
                            .tabItem { Label("Tasks", systemImage: "checklist") }
                        PlannerView(model: model)
                            .tabItem { Label("Plan", systemImage: "calendar.day.timeline.left") }
                        SettingsView(model: model)
                            .tabItem { Label("Settings", systemImage: "gearshape") }
                    }
                    .padding()
                }
            } else {
                VaultSetupView(model: model)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.isBusy { ProgressView().padding() }
        }
        .alert("FocusPilot", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct FocusBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.focus.phase == .breakTime ? "cup.and.saucer.fill" : "scope")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.focus.phase == .breakTime ? "Break" : "Current task")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.focus.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
            Text(model.focus.displayTime)
                .font(.title.monospacedDigit().bold())
            Button(model.focus.phase == .paused ? "Resume" : "Pause") {
                model.toggleFocusPause()
            }
            Button("Stop", role: .destructive) {
                model.stopFocus()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}

private struct VaultSetupView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "scope").font(.system(size: 64)).foregroundStyle(.tint)
            Text("Welcome to FocusPilot").font(.largeTitle.bold())
            Text("Choose a separate folder for your encrypted, Git-versioned task vault.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Create Vault") { chooseCreateFolder() }
                    .buttonStyle(.borderedProminent)
                Button("Open Existing Vault") { chooseExistingFolder() }
            }
            Text("Keep the exported recovery key outside the repository. Without it, encrypted data cannot be recovered.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(40)
    }

    private func chooseCreateFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Create Vault Here"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.createVault(at: url) }
    }

    private func chooseExistingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Vault"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let keyPanel = NSOpenPanel()
        keyPanel.canChooseDirectories = false
        keyPanel.canChooseFiles = true
        keyPanel.allowedContentTypes = [.json]
        keyPanel.prompt = "Use Recovery Key"
        let recoveryURL = keyPanel.runModal() == .OK ? keyPanel.url : nil
        Task { await model.openVault(at: url, recoveryFile: recoveryURL) }
    }
}
