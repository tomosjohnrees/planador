import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var addingToToday = true
    @State private var showingAdd = false
    @State private var editingTask: PlanTask?
    let openFocus: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Plan", date: store.now)
                taskSection("Today", tasks: store.todayTasks, today: true)
                Hairline().padding(.vertical, 35)
                taskSection("Backlog", tasks: store.backlogTasks, today: false)
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 44)
            .padding(.top, 49)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingAdd) {
            TaskEditor(task: nil, toToday: addingToToday) { title, minutes, notes in
                store.addTask(title: title, estimatedMinutes: minutes, notes: notes, toToday: addingToToday)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditor(task: task, toToday: task.plannedDate != nil) { title, minutes, notes in
                var changed = task
                changed.title = title
                changed.estimatedMinutes = minutes
                changed.notes = notes
                store.updateTask(changed)
            }
        }
    }

    private func taskSection(_ title: String, tasks: [PlanTask], today: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 18, weight: .medium))
                Spacer()
                Button {
                    addingToToday = today
                    showingAdd = true
                } label: {
                    Label("Add task", systemImage: "plus")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)

            if tasks.isEmpty {
                Text(today ? "Choose a task from your backlog, or add one for today." : "Capture tasks here for later.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 18)
            } else {
                ForEach(tasks) { task in
                    taskRow(task, today: today)
                }
            }
        }
    }

    private func taskRow(_ task: PlanTask, today: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "circle.grid.2x3")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
                Button { store.complete(task.id) } label: {
                    Image(systemName: "square")
                        .font(.system(size: 21, weight: .ultraLight))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete \(task.title)")
                Button {
                    store.selectForFocus(task.id)
                    openFocus()
                } label: {
                    Text(task.title)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(DurationLabel.short(task.estimatedMinutes))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .frame(height: 46)
            .contextMenu {
                Button("Focus on task") { store.selectForFocus(task.id); openFocus() }
                Button("Edit task") { editingTask = task }
                Button("Move up") { store.moveWithinList(task.id, by: -1) }
                Button("Move down") { store.moveWithinList(task.id, by: 1) }
                if today {
                    Button("Move to backlog") { store.move(task.id, to: nil) }
                    Button("Move to tomorrow") { store.move(task.id, to: store.tomorrow) }
                } else {
                    Button("Move to today") { store.move(task.id, to: store.today) }
                }
                Divider()
                Button("Delete task", role: .destructive) { store.delete(task.id) }
            }
            Hairline()
        }
    }
}

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var minutes: Int
    @State private var notes: String
    @FocusState private var titleFocused: Bool
    let isEditing: Bool
    let toToday: Bool
    let save: (String, Int, String) -> Void

    init(task: PlanTask?, toToday: Bool, save: @escaping (String, Int, String) -> Void) {
        _title = State(initialValue: task?.title ?? "")
        _minutes = State(initialValue: task?.estimatedMinutes ?? 25)
        _notes = State(initialValue: task?.notes ?? "")
        isEditing = task != nil
        self.toToday = toToday
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEditing ? "Edit task" : "Add to \(toToday ? "Today" : "Backlog")")
                .font(.system(size: 25, design: .serif))
            TextField("What needs doing?", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit(submit)
            HStack {
                Text("Estimate")
                Spacer()
                Stepper(value: $minutes, in: 5...480, step: 5) {
                    Text(DurationLabel.short(minutes)).monospacedDigit()
                }
                .fixedSize()
            }
            Text("Notes").font(.system(size: 13)).foregroundStyle(Theme.muted)
            TextEditor(text: $notes)
                .font(.system(size: 13))
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditing ? "Save" : "Add task", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 430)
        .onAppear { titleFocused = true }
    }

    private func submit() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        save(title.trimmingCharacters(in: .whitespacesAndNewlines), minutes, notes)
        dismiss()
    }
}

enum DurationLabel {
    static func short(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    static func summary(_ seconds: TimeInterval) -> String {
        if seconds > 0 && seconds < 60 { return "<1m" }
        let minutes = Int(seconds / 60)
        return short(minutes)
    }
}
