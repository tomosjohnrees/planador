import SwiftUI

struct MenuBarTimerLabel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Label {
            switch store.data.clock.phase {
            case .breakReady: Text("Break")
            case .ready: Text("Ready")
            case .work, .breakTime:
                if store.data.clock.startedAt != nil || store.data.clock.elapsedBeforeRun > 0 {
                    Text(DurationLabel.clock(store.data.clock.remaining(at: store.now))).monospacedDigit()
                } else {
                    Text("Planador")
                }
            }
        } icon: {
            Image(systemName: store.data.clock.phase == .breakTime ? "cup.and.saucer" :
                (store.data.clock.startedAt == nil ? "timer" : "circle.dotted.circle"))
        }
        .accessibilityLabel("Planador timer")
    }
}

struct MenuBarTimerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Planador").font(.headline)
                Spacer()
                Text(store.data.clock.startedAt == nil ? "Paused" : "Running")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !store.focusableTasks.isEmpty {
                Menu {
                    ForEach(store.focusableTasks) { task in
                        Button(task.title) { store.selectForFocus(task.id) }
                    }
                } label: {
                    Text(store.selectedTask?.title ?? "Choose a task").lineLimit(2)
                }
                .accessibilityLabel("Choose focus task")
            } else {
                Text("No tasks available. Add one in Plan.").font(.caption).foregroundStyle(.secondary)
            }
            Text(phaseTitle).font(.caption).foregroundStyle(.secondary)
            Text(DurationLabel.clock(store.data.clock.remaining(at: store.now)))
                .font(.system(size: 38, weight: .light)).monospacedDigit()
            if store.data.clock.phase == .breakReady {
                Button("Start break") { store.startBreak() }.buttonStyle(.borderedProminent)
                Button("Skip break") { store.skipBreak() }
            } else {
                HStack {
                    Button(store.data.clock.startedAt == nil ? "Start / Resume" : "Pause") { store.toggleTimer() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.data.clock.startedAt == nil && !store.canStartTimer)
                    Button("Reset") { store.resetTimer() }
                        .disabled(store.data.clock.phase == .ready)
                }
            }
            if let task = store.selectedTask, task.completedAt == nil {
                Button("Complete task") { store.complete(task.id) }
            }
            Divider()
            HStack {
                Button("Open Planador") { showMainWindow() }
                Spacer()
                Button("Add task") {
                    store.section = .plan
                    store.newTaskRequested = true
                    showMainWindow()
                }
            }
            Button("Quit Planador") { NSApp.terminate(nil) }
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 310)
    }

    private var phaseTitle: String {
        switch store.data.clock.phase {
        case .work: return "Focus time"
        case .breakReady: return "Focus complete — time to pause"
        case .breakTime: return "Break time"
        case .ready: return "Ready for your next session"
        }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
