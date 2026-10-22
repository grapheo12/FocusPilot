import SwiftUI

@main
struct FocusPilotApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .frame(width: 340)
        } label: {
            Label(model.menuTitle, systemImage: model.focus.phase == .breakTime ? "cup.and.saucer.fill" : "scope")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("FocusPilot") {
            MainView(model: model)
                .frame(minWidth: 820, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
    }
}
