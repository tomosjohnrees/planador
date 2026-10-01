import SwiftUI

@main
struct PlanadorApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        Window("Planador", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 850, minHeight: 650)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { PlanadorCommands(store: store) }
        MenuBarExtra {
            MenuBarTimerView().environmentObject(store)
        } label: {
            MenuBarTimerLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct PlanadorCommands: Commands {
    @ObservedObject var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New task") {
                store.section = .plan
                store.newTaskRequested = true
                showMainWindow()
            }.keyboardShortcut("n")
        }
        CommandGroup(after: .textEditing) {
            Button("Find tasks") {
                store.section = .search
                store.searchRequested = true
                showMainWindow()
            }
                .keyboardShortcut("f")
        }
        CommandMenu("Planador") {
            Button("Plan") { store.section = .plan; showMainWindow() }.keyboardShortcut("1")
            Button("Focus") { store.section = .focus; showMainWindow() }.keyboardShortcut("2")
            Button("Review") { store.section = .review; showMainWindow() }.keyboardShortcut("3")
            Divider()
            Button(store.data.clock.startedAt == nil ? "Start / Resume timer" : "Pause timer") {
                store.toggleTimer()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(store.data.clock.startedAt == nil && !store.canStartTimer)
        }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
