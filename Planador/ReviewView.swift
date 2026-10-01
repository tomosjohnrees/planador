import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var expandedTaskID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Review", date: store.now)
                HStack(spacing: 0) {
                    metric("\(store.completedToday.count)", caption: "Completed today")
                    Hairline().frame(width: 1, height: 60)
                    metric("\(store.todayTasks.count)", caption: "Unfinished today")
                    Hairline().frame(width: 1, height: 60)
                    metric(DurationLabel.summary(store.focusedToday), caption: "Total focused time")
                }
                .padding(.bottom, 40)
                Hairline()
                sectionTitle("Completed today")
                if store.completedToday.isEmpty {
                    empty("Completed tasks will appear here.")
                } else {
                    ForEach(store.completedToday) { task in
                        taskRow(task, complete: true)
                    }
                }
                Hairline().padding(.top, 30)
                sectionTitle("Unfinished today")
                if store.todayTasks.isEmpty {
                    empty("You’re all caught up for today.")
                } else {
                    ForEach(store.todayTasks) { task in
                        taskRow(task, complete: false)
                    }
                }
                if !store.completedEarlier.isEmpty {
                    Hairline().padding(.top, 30)
                    sectionTitle("Completed earlier")
                    ForEach(store.completedEarlier) { task in
                        taskRow(task, complete: true, showDate: true)
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

    private func metric(_ value: String, caption: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .medium))
            .padding(.top, 25)
            .padding(.bottom, 10)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            .padding(.vertical, 18)
    }

    private func taskRow(_ task: PlanTask, complete: Bool, showDate: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    if complete { store.reopen(task.id) }
                    else { store.complete(task.id) }
                } label: {
                    Image(systemName: complete ? "checkmark.square.fill" : "square")
                        .font(.system(size: 21, weight: complete ? .regular : .ultraLight))
                        .foregroundStyle(complete ? Theme.green : Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(complete ? "Reopen \(task.title)" : "Complete \(task.title)")
                Text(task.title)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer()
                if showDate, let completedAt = task.completedAt {
                    Text(completedAt, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedTaskID = expandedTaskID == task.id ? nil : task.id
                    }
                } label: {
                    Label(expandedTaskID == task.id ? "Hide notes" : "Notes",
                          systemImage: "note.text")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expandedTaskID == task.id ?
                    "Hide notes for \(task.title)" : "Notes for \(task.title)")
            }
            .frame(height: 46)
            if expandedTaskID == task.id {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Notes")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                    TextEditor(text: Binding(
                        get: { store.data.tasks.first(where: { $0.id == task.id })?.notes ?? "" },
                        set: { store.updateNotes($0, for: task.id) }
                    ))
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(height: 120)
                    .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 0.5))
                    .accessibilityLabel("Notes for \(task.title)")
                    Text("Changes save automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.leading, 35)
                .padding(.bottom, 15)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Hairline()
            if !complete {
                HStack {
                    Spacer()
                    Button {
                        store.move(task.id, to: store.tomorrow)
                    } label: {
                        Label("Tomorrow", systemImage: "calendar")
                    }
                    Button {
                        store.move(task.id, to: nil)
                    } label: {
                        Label("Backlog", systemImage: "square.stack")
                    }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12))
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
        }
    }
}
