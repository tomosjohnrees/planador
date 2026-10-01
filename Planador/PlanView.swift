import SwiftUI

private enum PlanPeriod: String, CaseIterable, Identifiable {
    case today = "Today", tomorrow = "Tomorrow", upcoming = "Upcoming"
    var id: Self { self }
}

struct PlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var period: PlanPeriod = .today
    @State private var upcomingDate = Date()
    @State private var addingSection: String?
    @State private var targetedPeriod: PlanPeriod?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Plan", date: store.now)
                HStack(spacing: 4) {
                    ForEach(PlanPeriod.allCases) { item in
                        Button { period = item } label: {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: period == item ? .medium : .regular))
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(period == item || targetedPeriod == item ? Theme.paleGreen : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(period == item ? .isSelected : [])
                        .help("View \(item.rawValue), or drop a task here to schedule it")
                        .onTaskDrop(isTargeted: Binding(
                            get: { targetedPeriod == item },
                            set: { targetedPeriod = $0 ? item : nil }
                        )) { items in
                            let date = item == .today ? store.today :
                                (item == .tomorrow ? store.tomorrow : max(upcomingDate, store.dayAfterTomorrow))
                            guard store.acceptTaskDrop(items, on: date) else { return false }
                            period = item
                            return true
                        }
                    }
                }
                .padding(4)
                .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 28)

                switch period {
                case .today:
                    if !store.carriedOverTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Carried over").font(.system(size: 18, weight: .medium))
                            Text("Unfinished from earlier days. Choose today, another date, or backlog.")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            ForEach(store.carriedOverTasks) { task in
                                TaskRow(task: task, showDate: true)
                            }
                        }
                        Hairline().padding(.vertical, 28)
                    }
                    taskSection("Today", key: "today", date: store.today)
                case .tomorrow:
                    taskSection("Tomorrow", key: "tomorrow", date: store.tomorrow)
                case .upcoming:
                    DatePicker("Plan for", selection: $upcomingDate, in: store.dayAfterTomorrow..., displayedComponents: .date)
                        .padding(.bottom, 24)
                    ForEach(upcomingDates, id: \.self) { date in
                        taskSection(date.formatted(date: .abbreviated, time: .omitted),
                                    key: "date-\(date.timeIntervalSinceReferenceDate)", date: date)
                            .padding(.bottom, 26)
                    }
                }
                Hairline().padding(.vertical, 32)
                taskSection("Backlog", key: "backlog", date: nil)
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 44)
            .padding(.top, 49)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            upcomingDate = max(upcomingDate, store.dayAfterTomorrow)
            consumeNewTaskRequest()
        }
        .onChange(of: store.newTaskRequested) { _, _ in consumeNewTaskRequest() }
        .onChange(of: store.today) { _, _ in
            upcomingDate = max(upcomingDate, store.dayAfterTomorrow)
        }
    }

    private var upcomingDates: [Date] {
        Set(store.upcomingDates + [Calendar.current.startOfDay(for: max(upcomingDate, store.dayAfterTomorrow))]).sorted()
    }

    private func consumeNewTaskRequest() {
        guard store.newTaskRequested else { return }
        period = .today
        addingSection = "today"
        store.newTaskRequested = false
    }

    private func taskSection(_ title: String, key: String, date: Date?) -> some View {
        let tasks = store.tasks(on: date)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 18, weight: .medium))
                Spacer()
                Button { addingSection = key } label: {
                    Label("Add task", systemImage: "plus").font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)

            if addingSection == key {
                TaskEditor(task: nil, plannedDate: date, save: { title, notes, plannedDate in
                    store.addTask(title: title, notes: notes, plannedDate: plannedDate)
                    addingSection = nil
                }, cancel: { addingSection = nil })
                .padding(18)
                .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 0.7))
            }
            ForEach(tasks) { TaskRow(task: $0) }
            TaskDropArea(date: date, empty: tasks.isEmpty)
        }
    }
}

private struct TaskDropArea: View {
    @EnvironmentObject private var store: AppStore
    let date: Date?
    let empty: Bool
    @State private var targeted = false

    var body: some View {
        Text(empty ? "Add a task or drop one here." : "Drop here to move to the end")
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, minHeight: empty ? 48 : 28, alignment: .leading)
            .padding(.horizontal, 10)
            .background(targeted ? Theme.paleGreen : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .onTaskDrop(isTargeted: $targeted) { items in
                store.acceptTaskDrop(items, on: date)
            }
            .accessibilityLabel(date == nil ? "Drop task in backlog" : "Drop task on \(date!.formatted(date: .abbreviated, time: .omitted))")
    }
}

struct TaskEditor: View {
    @State private var title: String
    @State private var notes: String
    @State private var scheduled: Bool
    @State private var date: Date
    @FocusState private var titleFocused: Bool
    let isEditing: Bool
    let save: (String, String, Date?) -> Void
    let cancel: () -> Void

    init(task: PlanTask?, plannedDate: Date?, save: @escaping (String, String, Date?) -> Void,
         cancel: @escaping () -> Void) {
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _scheduled = State(initialValue: plannedDate != nil)
        _date = State(initialValue: plannedDate ?? Date())
        isEditing = task != nil
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "Edit task" : "Add task")
                .font(.system(size: isEditing ? 25 : 17, design: isEditing ? .serif : .default))
            TextField("What needs doing?", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit(submit)
            Toggle("Schedule for a day", isOn: $scheduled)
            if scheduled {
                DatePicker("Day", selection: $date, displayedComponents: .date)
            } else {
                Text("Kept in Backlog until you schedule it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Text("Notes").font(.system(size: 13)).foregroundStyle(Theme.muted)
            TextEditor(text: $notes)
                .font(.system(size: 13))
                .frame(height: isEditing ? 110 : 75)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line))
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add task", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { DispatchQueue.main.async { titleFocused = true } }
    }

    private func submit() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        save(clean, notes, scheduled ? date : nil)
    }
}

enum DurationLabel {
    private static func short(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    static func summary(_ seconds: TimeInterval) -> String {
        if seconds > 0 && seconds < 60 { return "<1m" }
        return short(Int(seconds / 60))
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(max(0, seconds)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
