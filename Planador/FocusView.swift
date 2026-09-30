import SwiftUI

struct FocusView: View {
    @EnvironmentObject private var store: AppStore

    private var availableTasks: [PlanTask] { store.todayTasks + store.backlogTasks }
    private var phase: FocusPhase { store.data.clock.phase }
    private var task: PlanTask? {
        guard let selected = store.selectedTask, selected.completedAt == nil else { return nil }
        return selected
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Focus", date: store.now)

                if availableTasks.isEmpty && phase == .work {
                    emptyState
                } else {
                    if !availableTasks.isEmpty { taskPicker }
                    if phase == .breakReady {
                        workCompletePrompt
                    } else if phase == .breakTime || phase == .ready || task != nil {
                        timer
                    }
                    if let task {
                        notes(for: task)
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 44)
            .padding(.top, 49)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to focus on yet")
                .font(.system(size: 19, design: .serif))
            Text("Add a task in Plan to start a focus session.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 25)
    }

    private var workCompletePrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.green)
            Text("Time to pause")
                .font(.system(size: 29, design: .serif))
            Text("Your focus session is complete. Stop working and take a break.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Start \(store.data.timerSettings.breakMinutes)-minute break") {
                store.startBreak()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.green)
            .controlSize(.large)
            Button("Skip break") { store.skipBreak() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 25)
        .padding(.vertical, 34)
        .background(Theme.paleGreen.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 30)
        .padding(.bottom, 25)
    }

    private var taskPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current task")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Menu {
                ForEach(availableTasks) { item in
                    Button(item.title) { store.selectForFocus(item.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(task?.title ?? "Choose a task")
                        .font(.system(size: 23, design: .serif))
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Current task")
        }
    }

    private var timer: some View {
        let remaining = store.data.clock.remaining(at: store.now)
        let progress = 1 - remaining / Double(store.data.clock.durationMinutes * 60)

        return VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Theme.paleGreen, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 5) {
                    Text(clockText(remaining))
                        .font(.system(size: 65, weight: .light, design: .serif))
                        .monospacedDigit()
                    Text(phase == .breakTime ? "Break time" :
                            (phase == .ready ? "Next focus session" : "Focus time"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 265, height: 265)
            .padding(.top, 28)

            if phase == .ready {
                Text(task == nil ? "Break complete. Choose a task to continue." :
                        "Break complete. Start when you're ready.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Button("Start next session") { store.startTimer() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.green)
                    .disabled(task == nil)
                    .padding(.bottom, 24)
            } else {
                HStack(spacing: 42) {
                    RoundAction(symbol: "arrow.counterclockwise", label: "Reset timer") {
                        store.resetTimer()
                    }
                    Button {
                        if store.data.clock.startedAt == nil { store.startTimer() }
                        else { store.pauseTimer() }
                    } label: {
                        Image(systemName: store.data.clock.startedAt == nil ? "play.fill" : "pause.fill")
                            .font(.system(size: 21))
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Theme.green, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.data.clock.startedAt == nil ?
                        (phase == .breakTime ? "Resume break" : "Start focus") :
                        (phase == .breakTime ? "Pause break" : "Pause focus"))
                    if let task {
                        RoundAction(symbol: "checkmark", label: "Complete task") {
                            store.complete(task.id)
                        }
                    } else {
                        Color.clear.frame(width: 46, height: 46)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func notes(for task: PlanTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Text("Notes")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .padding(.top, 9)
            TextEditor(text: Binding(
                get: { store.selectedTask?.notes ?? "" },
                set: { store.updateNotes($0, for: task.id) }
            ))
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(height: 125)
            .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 0.5))
            .accessibilityLabel("Task notes")
        }
    }

    private func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
