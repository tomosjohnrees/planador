import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published private(set) var now = Date()
    @Published var errorMessage: String?

    private let fileURL: URL
    private var maySave = true
    nonisolated(unsafe) private var ticker: Timer?
    private let calendar = Calendar.current

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planador", isDirectory: true)
        self.fileURL = fileURL ?? support.appendingPathComponent("data.json")
        do {
            let bytes = try Data(contentsOf: self.fileURL)
            data = try JSONDecoder().decode(AppData.self, from: bytes)
        } catch CocoaError.fileReadNoSuchFile {
            data = AppData()
        } catch {
            data = AppData()
            let backupURL = self.fileURL.deletingPathExtension()
                .appendingPathExtension("unreadable-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: self.fileURL, to: backupURL)
                errorMessage = "Saved data could not be opened. A copy was kept at \(backupURL.path)."
            } catch {
                maySave = false
                errorMessage = "Saved data could not be opened. Changes will not be saved until the data file is repaired."
            }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        ticker?.tolerance = 0.1
        tick()
    }

    deinit { ticker?.invalidate() }

    var today: Date { calendar.startOfDay(for: now) }
    var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: today)! }

    var todayTasks: [PlanTask] {
        data.tasks.filter { $0.completedAt == nil && $0.plannedDate.map { calendar.isDate($0, inSameDayAs: today) } == true }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var backlogTasks: [PlanTask] {
        data.tasks.filter { $0.completedAt == nil && $0.plannedDate == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var completedToday: [PlanTask] {
        data.tasks.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: today) } == true }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    var selectedTask: PlanTask? { data.tasks.first { $0.id == data.clock.taskID } }

    var focusedToday: TimeInterval {
        let interval = DateInterval(start: today, end: tomorrow)
        let saved = data.sessions.reduce(0.0) { sum, session in
            let overlapStart = max(session.startedAt, interval.start)
            let overlapEnd = min(session.endedAt, interval.end)
            return sum + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
        if let started = data.clock.startedAt {
            return saved + max(0, min(now, interval.end).timeIntervalSince(max(started, interval.start)))
        }
        return saved
    }

    func addTask(title: String, estimatedMinutes: Int, notes: String, toToday: Bool) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let order = (data.tasks.map(\.sortOrder).max() ?? -1) + 1
        data.tasks.append(PlanTask(title: cleanTitle, estimatedMinutes: estimatedMinutes,
                                   notes: notes, plannedDate: toToday ? today : nil, sortOrder: order))
        save()
    }

    func updateNotes(_ notes: String, for id: UUID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].notes = notes
        save()
    }

    func updateTask(_ task: PlanTask) {
        guard let index = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        data.tasks[index] = task
        save()
    }

    func complete(_ id: UUID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        if data.clock.taskID == id { pauseFocus() }
        data.tasks[index].completedAt = now
        save()
    }

    func reopen(_ id: UUID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].completedAt = nil
        data.tasks[index].plannedDate = today
        save()
    }

    func move(_ id: UUID, to date: Date?) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].plannedDate = date
        data.tasks[index].sortOrder = (data.tasks.map(\.sortOrder).max() ?? -1) + 1
        save()
    }

    func moveWithinList(_ id: UUID, by offset: Int) {
        guard offset == -1 || offset == 1,
              let task = data.tasks.first(where: { $0.id == id }) else { return }
        let siblings = data.tasks
            .filter { $0.completedAt == nil && $0.plannedDate == task.plannedDate }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard let position = siblings.firstIndex(where: { $0.id == id }),
              siblings.indices.contains(position + offset),
              let first = data.tasks.firstIndex(where: { $0.id == id }),
              let second = data.tasks.firstIndex(where: { $0.id == siblings[position + offset].id }) else { return }
        let originalOrder = data.tasks[first].sortOrder
        data.tasks[first].sortOrder = data.tasks[second].sortOrder
        data.tasks[second].sortOrder = originalOrder
        save()
    }

    func delete(_ id: UUID) {
        if data.clock.taskID == id { pauseFocus(); data.clock = FocusClock() }
        data.tasks.removeAll { $0.id == id }
        save()
    }

    func selectForFocus(_ id: UUID) {
        guard data.tasks.contains(where: { $0.id == id && $0.completedAt == nil }) else { return }
        guard data.clock.taskID != id else { return }
        pauseFocus()
        data.clock = FocusClock(taskID: id, durationMinutes: data.clock.durationMinutes)
        save()
    }

    func setFocusDuration(_ minutes: Int) {
        guard [15, 25, 45, 60].contains(minutes) else { return }
        pauseFocus()
        data.clock.durationMinutes = minutes
        data.clock.elapsedBeforeRun = 0
        save()
    }

    func startFocus() {
        guard selectedTask?.completedAt == nil, data.clock.startedAt == nil else { return }
        if data.clock.remaining(at: now) == 0 { data.clock.elapsedBeforeRun = 0 }
        data.clock.startedAt = Date()
        now = Date()
        save()
    }

    func pauseFocus() {
        guard let started = data.clock.startedAt, let taskID = data.clock.taskID else { return }
        let end = min(Date(), started.addingTimeInterval(data.clock.remaining(at: started)))
        if end > started {
            data.sessions.append(FocusSession(taskID: taskID, startedAt: started, endedAt: end))
            data.clock.elapsedBeforeRun += end.timeIntervalSince(started)
        }
        data.clock.startedAt = nil
        now = Date()
        save()
    }

    func resetFocus() {
        pauseFocus()
        data.clock.elapsedBeforeRun = 0
        save()
    }

    private func tick() {
        now = Date()
        if data.clock.startedAt != nil && data.clock.remaining(at: now) <= 0 { pauseFocus() }
    }

    private func save() {
        guard maySave else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: fileURL, options: .atomic)
        } catch {
            errorMessage = "Your changes could not be saved: \(error.localizedDescription)"
        }
    }
}
