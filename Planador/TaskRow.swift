import SwiftUI
import UniformTypeIdentifiers

struct TaskRow: View {
    @EnvironmentObject private var store: AppStore
    let task: PlanTask
    var showDate = false
    var allowsDrop = true
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var editingDetails = false
    @State private var scheduling = false
    @State private var scheduleDate = Date()
    @State private var targeted = false
    @State private var pendingDeletion: PlanTask?
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if task.completedAt == nil {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(Theme.muted)
                        .frame(width: 20, height: 34)
                        .contentShape(Rectangle())
                        .onDrag { TaskDrag.itemProvider(for: task.id) }
                        .help("Drag to reorder or move to another day")
                        .accessibilityLabel("Drag \(task.title)")
                }
                Button {
                    if task.completedAt == nil { store.complete(task.id) }
                    else { store.reopen(task.id) }
                } label: {
                    Image(systemName: task.completedAt == nil ? "square" : "checkmark.square.fill")
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(task.completedAt == nil ? Theme.muted : Theme.green)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(task.completedAt == nil ? "Complete" : "Reopen") \(task.title)")

                if editingTitle {
                    TextField("Task title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .onSubmit(commitTitle)
                        .onExitCommand { editingTitle = false; titleFocused = false }
                        .onChange(of: titleFocused) { _, focused in
                            if !focused && editingTitle { commitTitle() }
                        }
                } else {
                    Button {
                        titleDraft = task.title
                        editingTitle = true
                        titleFocused = true
                    } label: {
                        Text(task.title).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit title")
                }
                if task.completedAt == nil {
                    Button { store.focusTask(task.id) } label: {
                        Image(systemName: "play.circle").font(.system(size: 17))
                    }
                    .buttonStyle(.plain)
                    .help("Focus on task")
                    .accessibilityLabel("Focus on \(task.title)")
                }
                Button {
                    scheduleDate = task.plannedDate ?? store.today
                    scheduling = true
                } label: { Image(systemName: "calendar") }
                .buttonStyle(.plain)
                .disabled(task.completedAt != nil)
                .help("Schedule task")
                .accessibilityLabel("Schedule \(task.title)")
                .popover(isPresented: $scheduling) { schedulePicker }
                Button { editingDetails = true } label: { Image(systemName: "note.text") }
                    .buttonStyle(.plain)
                    .help("Edit notes and details")
                    .accessibilityLabel("Edit notes for \(task.title)")
                Button { pendingDeletion = task } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .help("Delete task")
                    .accessibilityLabel("Delete \(task.title)")
            }
            .font(.system(size: 14))
            .frame(minHeight: 46)
            if showDate {
                Text(statusText).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, task.completedAt == nil ? 55 : 33)
                    .padding(.bottom, 8)
            }
            Hairline()
        }
        .padding(.horizontal, 4)
        .background(targeted ? Theme.paleGreen : .clear, in: RoundedRectangle(cornerRadius: 7))
        .onTaskDrop(isTargeted: $targeted, enabled: allowsDrop && task.completedAt == nil) { items in
            store.acceptTaskDrop(items, on: task.plannedDate, before: task.id)
        }
        .contextMenu {
            if task.completedAt == nil {
                Button("Focus on task") { store.focusTask(task.id) }
                Button("Move to today") { store.move(task.id, to: store.today) }
                Button("Move to tomorrow") { store.move(task.id, to: store.tomorrow) }
                Button("Move to backlog") { store.move(task.id, to: nil) }
                Button("Choose date…") { scheduleDate = task.plannedDate ?? store.today; scheduling = true }
                Divider()
                Button("Move up") { store.moveWithinList(task.id, by: -1) }
                Button("Move down") { store.moveWithinList(task.id, by: 1) }
            }
            Button("Edit task…") { editingDetails = true }
            Divider()
            Button("Delete task", role: .destructive) { pendingDeletion = task }
        }
        .sheet(isPresented: $editingDetails) {
            TaskEditor(task: task, plannedDate: task.plannedDate, save: { title, notes, date in
                // Read the current task so another view's changes are not overwritten.
                if var changed = store.data.tasks.first(where: { $0.id == task.id }) {
                    changed.title = title
                    changed.notes = notes
                    changed.plannedDate = date
                    store.updateTask(changed)
                }
                editingDetails = false
            }, cancel: { editingDetails = false })
            .padding(28).frame(width: 440)
        }
        .taskDeletionAlert(task: $pendingDeletion)
    }

    private var statusText: String {
        if let completed = task.completedAt {
            return "Completed \(completed.formatted(date: .abbreviated, time: .omitted))"
        }
        guard let date = task.plannedDate else { return "Backlog" }
        return "\(date < store.today ? "Carried over from" : "Planned for") \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private var schedulePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Schedule task").font(.headline)
            HStack {
                Button("Today") { store.move(task.id, to: store.today); scheduling = false }
                Button("Tomorrow") { store.move(task.id, to: store.tomorrow); scheduling = false }
                Button("Backlog") { store.move(task.id, to: nil); scheduling = false }
            }
            DatePicker("Day", selection: $scheduleDate, displayedComponents: .date)
            HStack {
                Button("Cancel") { scheduling = false }
                Spacer()
                Button("Apply") { store.move(task.id, to: scheduleDate); scheduling = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 340)
    }

    private func commitTitle() {
        store.renameTask(task.id, to: titleDraft)
        editingTitle = false
        titleFocused = false
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Search", date: store.now)
                TextField("Search task titles and notes", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .accessibilityLabel("Search all tasks")
                let results = store.searchTasks(query)
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Find tasks across every day, your backlog, and completed work.")
                        .foregroundStyle(Theme.muted)
                } else if results.isEmpty {
                    Text("No tasks found.").foregroundStyle(Theme.muted)
                } else {
                    Text("\(results.count) \(results.count == 1 ? "task" : "tasks")")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    LazyVStack(spacing: 8) {
                        ForEach(results) { TaskRow(task: $0, showDate: true, allowsDrop: false) }
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 44).padding(.vertical, 49)
            .frame(maxWidth: .infinity)
        }
        .onAppear { focusSearch() }
        .onChange(of: store.searchRequested) { _, requested in
            if requested { focusSearch() }
        }
    }

    private func focusSearch() {
        store.searchRequested = false
        DispatchQueue.main.async { searchFocused = true }
    }
}

enum TaskDrag {
    static let typeIdentifier = UTType.utf8PlainText.identifier

    static func itemProvider(for id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        let bytes = Data("planador-task:\(id.uuidString)".utf8)
        // Register only text. NSString also advertises this colon-prefixed payload
        // as a URL, which can make macOS route the drag to the wrong representation.
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
            completion(bytes, nil)
            return nil
        }
        return provider
    }
}

extension View {
    func onTaskDrop(isTargeted: Binding<Bool>, enabled: Bool = true,
                    perform: @escaping @MainActor @Sendable ([String]) -> Bool) -> some View {
        onDrop(of: [UTType.utf8PlainText], isTargeted: enabled ? isTargeted : nil) { providers in
            guard enabled, providers.count == 1, let provider = providers.first,
                  provider.hasItemConformingToTypeIdentifier(TaskDrag.typeIdentifier) else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: TaskDrag.typeIdentifier) { bytes, _ in
                guard let bytes, let text = String(data: bytes, encoding: .utf8) else { return }
                Task { @MainActor in _ = perform([text]) }
            }
            return true
        }
    }
}
