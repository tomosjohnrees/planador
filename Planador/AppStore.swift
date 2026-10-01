import AppKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published private(set) var now = Date()
    @Published var errorMessage: String?
    @Published var section: AppSection = .plan
    @Published var newTaskRequested = false
    @Published var searchRequested = false
    weak var undoManager: UndoManager?

    private let notifications: CompletionNotifications?

    private let fileURL: URL
    private let completionSignal: ((FocusPhase) -> Void)?
    private let workChime: NSSound?
    private let breakChime: NSSound?
    private let managesDockBadge: Bool
    private var maySave = true
    nonisolated(unsafe) private var ticker: Timer?
    private let calendar = Calendar.current

    init(fileURL: URL? = nil, completionSignal: ((FocusPhase) -> Void)? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planador", isDirectory: true)
        self.fileURL = fileURL ?? support.appendingPathComponent("data.json")
        self.notifications = fileURL == nil ? CompletionNotifications() : nil
        self.completionSignal = completionSignal
        self.managesDockBadge = fileURL == nil
        self.workChime = Bundle.main.url(forResource: "FocusComplete", withExtension: "wav")
            .flatMap { NSSound(contentsOf: $0, byReference: false) }
        self.breakChime = Bundle.main.url(forResource: "BreakComplete", withExtension: "wav")
            .flatMap { NSSound(contentsOf: $0, byReference: false) }
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
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
        updateClock(at: Date(), announce: false)
        updateDockBadge()
    }

    deinit { ticker?.invalidate() }

    var today: Date { calendar.startOfDay(for: now) }
    var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: today)! }

    var dayAfterTomorrow: Date { calendar.date(byAdding: .day, value: 1, to: tomorrow)! }

    var backupFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "Planador-\(formatter.string(from: now))"
    }

    func tasks(on date: Date?) -> [PlanTask] {
        data.tasks.filter { $0.completedAt == nil && sameList($0.plannedDate, date) }
            .sorted(by: taskOrder)
    }

    private func sameList(_ first: Date?, _ second: Date?) -> Bool {
        switch (first, second) {
        case (nil, nil): return true
        case let (first?, second?): return calendar.isDate(first, inSameDayAs: second)
        default: return false
        }
    }

    private func taskOrder(_ first: PlanTask, _ second: PlanTask) -> Bool {
        first.sortOrder == second.sortOrder
            ? first.id.uuidString < second.id.uuidString : first.sortOrder < second.sortOrder
    }

    var todayTasks: [PlanTask] { tasks(on: today) }
    var tomorrowTasks: [PlanTask] { tasks(on: tomorrow) }
    var backlogTasks: [PlanTask] { tasks(on: nil) }
    var carriedOverTasks: [PlanTask] {
        data.tasks.filter { $0.completedAt == nil && ($0.plannedDate.map { $0 < today } ?? false) }
            .sorted(by: taskOrder)
    }
    var upcomingDates: [Date] {
        Set(data.tasks.compactMap { task -> Date? in
            guard task.completedAt == nil, let date = task.plannedDate,
                  date >= dayAfterTomorrow else { return nil }
            return calendar.startOfDay(for: date)
        }).sorted()
    }
    var focusableTasks: [PlanTask] { todayTasks + carriedOverTasks + backlogTasks }

    func searchTasks(_ query: String) -> [PlanTask] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return [] }
        return data.tasks.filter { task in
            terms.allSatisfy { term in
                task.title.localizedStandardContains(term) || task.notes.localizedStandardContains(term)
            }
        }.sorted { first, second in
            if (first.completedAt == nil) != (second.completedAt == nil) {
                return first.completedAt == nil
            }
            return taskOrder(first, second)
        }
    }

    var completedToday: [PlanTask] {
        data.tasks.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: today) } == true }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    var completedEarlier: [PlanTask] {
        data.tasks.filter { $0.completedAt.map { $0 < today } == true }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var selectedTask: PlanTask? { data.tasks.first { $0.id == data.clock.taskID } }

    var focusedToday: TimeInterval {
        let interval = DateInterval(start: today, end: tomorrow)
        let saved = data.sessions.reduce(0.0) { sum, session in
            let overlapStart = max(session.startedAt, interval.start)
            let overlapEnd = min(session.endedAt, interval.end)
            return sum + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
        if data.clock.phase == .work, let started = data.clock.startedAt {
            let workEnd = started.addingTimeInterval(data.clock.remaining(at: started))
            return saved + max(0, min(now, interval.end, workEnd).timeIntervalSince(max(started, interval.start)))
        }
        return saved
    }

    func addTask(title: String, notes: String, toToday: Bool) {
        addTask(title: title, notes: notes, plannedDate: toToday ? today : nil)
    }

    func addTask(title: String, notes: String, plannedDate: Date?) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        rememberTasks("Add task")
        let order = (data.tasks.map(\.sortOrder).max() ?? -1) + 1
        data.tasks.append(PlanTask(title: cleanTitle, notes: notes,
                                   plannedDate: plannedDate.map { calendar.startOfDay(for: $0) }, sortOrder: order))
        save()
    }

    func updateNotes(_ notes: String, for id: UUID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }),
              data.tasks[index].notes != notes else { return }
        rememberTasks("Edit notes")
        data.tasks[index].notes = notes
        save()
    }

    func renameTask(_ id: UUID, to title: String) {
        guard var task = data.tasks.first(where: { $0.id == id }) else { return }
        task.title = title
        updateTask(task)
    }

    func updateTask(_ task: PlanTask) {
        guard let index = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var changed = task
        changed.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        changed.plannedDate = task.plannedDate.map { calendar.startOfDay(for: $0) }
        guard !changed.title.isEmpty, changed != data.tasks[index] else { return }
        rememberTasks("Edit task")
        data.tasks[index] = changed
        reconcileFocusedTask()
        save()
    }

    func complete(_ id: UUID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id && $0.completedAt == nil }) else { return }
        rememberTasks("Complete task")
        if data.clock.taskID == id {
            changeFocusedTask(to: nextTaskID(after: id), at: Date())
        }
        data.tasks[index].completedAt = now
        save()
    }

    func reopen(_ id: UUID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id && $0.completedAt != nil }) else { return }
        rememberTasks("Reopen task")
        data.tasks[index].completedAt = nil
        data.tasks[index].plannedDate = today
        save()
    }

    func move(_ id: UUID, to date: Date?) {
        _ = placeTask(id, on: date)
    }

    func acceptTaskDrop(_ items: [String], on date: Date?, before targetID: UUID? = nil) -> Bool {
        guard items.count == 1, let item = items.first,
              item.hasPrefix("planador-task:"),
              let id = UUID(uuidString: String(item.dropFirst("planador-task:".count))) else { return false }
        return placeTask(id, on: date, before: targetID)
    }

    /// Dropping on a row inserts before it; dropping on a section appends.
    @discardableResult
    func placeTask(_ id: UUID, on date: Date?, before targetID: UUID? = nil) -> Bool {
        guard let index = data.tasks.firstIndex(where: { $0.id == id && $0.completedAt == nil }),
              targetID != id else { return false }
        var siblings = tasks(on: date).filter { $0.id != id }
        let insertion: Int
        if let targetID {
            guard let position = siblings.firstIndex(where: { $0.id == targetID }) else { return false }
            insertion = position
        } else {
            insertion = siblings.count
        }
        let previous = data.tasks
        var moved = data.tasks[index]
        moved.plannedDate = date.map { calendar.startOfDay(for: $0) }
        siblings.insert(moved, at: insertion)
        var changed = data.tasks
        for (order, sibling) in siblings.enumerated() {
            guard let taskIndex = changed.firstIndex(where: { $0.id == sibling.id }) else { continue }
            changed[taskIndex].plannedDate = sibling.plannedDate
            changed[taskIndex].sortOrder = order
        }
        guard changed != previous else { return true }
        rememberTasks("Move task")
        data.tasks = changed
        reconcileFocusedTask()
        save()
        return true
    }

    func moveWithinList(_ id: UUID, by offset: Int) {
        guard offset == -1 || offset == 1,
              let task = data.tasks.first(where: { $0.id == id && $0.completedAt == nil }) else { return }
        let siblings = tasks(on: task.plannedDate)
        guard let position = siblings.firstIndex(where: { $0.id == id }),
              siblings.indices.contains(position + offset) else { return }
        let target = offset == -1 ? siblings[position - 1].id :
            (siblings.indices.contains(position + 2) ? siblings[position + 2].id : nil)
        placeTask(id, on: task.plannedDate, before: target)
    }

    func delete(_ id: UUID) {
        guard data.tasks.contains(where: { $0.id == id }) else { return }
        rememberTasks("Delete task")
        if data.clock.taskID == id {
            changeFocusedTask(to: nextTaskID(after: id), at: Date())
        }
        data.tasks.removeAll { $0.id == id }
        save()
    }

    private func rememberTasks(_ name: String) {
        let tasks = data.tasks
        undoManager?.registerUndo(withTarget: self) { store in
            store.restoreTasks(tasks, actionName: name)
        }
        undoManager?.setActionName(name)
    }

    private func restoreTasks(_ tasks: [PlanTask], actionName: String) {
        rememberTasks(actionName)
        data.tasks = tasks
        // Task undo never rewinds the clock or discards logged work.
        reconcileFocusedTask()
        save()
    }

    private func reconcileFocusedTask() {
        guard let id = data.clock.taskID,
              !focusableTasks.contains(where: { $0.id == id }) else { return }
        changeFocusedTask(to: focusableTasks.first?.id, at: Date())
    }

    func focusTask(_ id: UUID) {
        guard let task = data.tasks.first(where: { $0.id == id && $0.completedAt == nil }) else { return }
        if let date = task.plannedDate, date >= tomorrow { move(id, to: today) }
        selectForFocus(id)
        section = .focus
    }

    var canStartTimer: Bool {
        switch data.clock.phase {
        case .breakReady: return false
        case .breakTime: return true
        case .ready: return selectedTask != nil && selectedTask?.completedAt == nil
        case .work: return (selectedTask != nil && selectedTask?.completedAt == nil) || data.clock.elapsedBeforeRun > 0
        }
    }

    func toggleTimer() {
        if data.clock.startedAt != nil { pauseTimer() }
        else if canStartTimer { startTimer() }
    }

    func selectForFocus(_ id: UUID) {
        guard data.tasks.contains(where: { $0.id == id && $0.completedAt == nil }) else { return }
        guard data.clock.taskID != id else { return }
        changeFocusedTask(to: id, at: Date())
        save()
    }

    private func nextTaskID(after id: UUID) -> UUID? {
        let tasks = focusableTasks
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return tasks.first?.id
        }
        return tasks.dropFirst(index + 1).first?.id
            ?? tasks.first(where: { $0.id != id })?.id
    }

    private func changeFocusedTask(to id: UUID?, at date: Date) {
        updateClock(at: date, announce: true)
        guard data.clock.taskID != id else { return }
        if data.clock.phase == .work, let started = data.clock.startedAt {
            let end = min(date, started.addingTimeInterval(data.clock.remaining(at: started)))
            if end > started {
                data.sessions.append(FocusSession(taskID: data.clock.taskID,
                                                  startedAt: started, endedAt: end))
                data.clock.elapsedBeforeRun += end.timeIntervalSince(started)
            }
            data.clock.startedAt = date
        }
        data.clock.taskID = id
    }

    func setWorkMinutes(_ minutes: Int) {
        guard (5...120).contains(minutes) else { return }
        data.timerSettings.workMinutes = minutes
        if data.clock.phase == .ready ||
            (data.clock.phase == .work && data.clock.startedAt == nil && data.clock.elapsedBeforeRun == 0) {
            data.clock.durationMinutes = minutes
        }
        save()
    }

    func setBreakMinutes(_ minutes: Int) {
        guard (1...30).contains(minutes) else { return }
        data.timerSettings.breakMinutes = minutes
        if data.clock.phase == .breakReady { data.clock.durationMinutes = minutes }
        save()
    }

    func startTimer() {
        guard data.clock.startedAt == nil else { return }
        guard data.clock.phase != .breakReady else { return }
        if data.clock.phase == .ready {
            guard selectedTask != nil, selectedTask?.completedAt == nil else { return }
            data.clock.phase = .work
            data.clock.durationMinutes = data.timerSettings.workMinutes
            data.clock.elapsedBeforeRun = 0
        } else if data.clock.phase == .work {
            guard (selectedTask != nil && selectedTask?.completedAt == nil) || data.clock.elapsedBeforeRun > 0 else { return }
        }
        now = Date()
        data.clock.startedAt = now
        updateDockBadge()
        save()
    }

    func startBreak(at date: Date = Date()) {
        guard data.clock.phase == .breakReady, data.clock.startedAt == nil else { return }
        now = date
        data.clock.phase = .breakTime
        data.clock.startedAt = date
        updateDockBadge()
        save()
    }

    func skipBreak() {
        guard data.clock.phase == .breakReady else { return }
        data.clock.phase = .ready
        data.clock.durationMinutes = data.timerSettings.workMinutes
        data.clock.elapsedBeforeRun = 0
        data.clock.startedAt = nil
        updateDockBadge()
        save()
    }

    func pauseTimer() {
        let date = Date()
        let previousPhase = data.clock.phase
        updateClock(at: date, announce: true)
        guard previousPhase == data.clock.phase, let started = data.clock.startedAt else { return }
        let end = min(date, started.addingTimeInterval(data.clock.remaining(at: started)))
        if end > started {
            if data.clock.phase == .work {
                data.sessions.append(FocusSession(taskID: data.clock.taskID,
                                                  startedAt: started, endedAt: end))
            }
            data.clock.elapsedBeforeRun += end.timeIntervalSince(started)
        }
        data.clock.startedAt = nil
        now = date
        updateDockBadge()
        save()
    }

    func resetTimer() {
        pauseTimer()
        data.clock.elapsedBeforeRun = 0
        updateDockBadge()
        save()
    }

    private func tick() {
        updateClock(at: Date(), announce: true)
    }

    func updateClock(at date: Date, announce: Bool = false) {
        now = date
        var changed = false
        for _ in 0..<2 {
            guard let started = data.clock.startedAt,
                  data.clock.remaining(at: date) <= 0 else { break }
            let end = started.addingTimeInterval(data.clock.remaining(at: started))
            switch data.clock.phase {
            case .work:
                if end > started {
                    data.sessions.append(FocusSession(taskID: data.clock.taskID,
                                                      startedAt: started, endedAt: end))
                }
                data.clock.phase = .breakReady
                data.clock.durationMinutes = data.timerSettings.breakMinutes
                data.clock.elapsedBeforeRun = 0
                data.clock.startedAt = nil
                if announce { signalCompletion(.work) }
            case .breakReady:
                data.clock.startedAt = nil
            case .breakTime:
                data.clock.phase = .ready
                data.clock.durationMinutes = data.timerSettings.workMinutes
                data.clock.elapsedBeforeRun = 0
                data.clock.startedAt = nil
                if announce { signalCompletion(.breakTime) }
            case .ready:
                data.clock.startedAt = nil
            }
            changed = true
        }
        if changed {
            // Leave the due system notification in place when the timer expires naturally.
            updateDockBadge(synchronizeNotification: false)
            save()
        }
    }

    private func signalCompletion(_ phase: FocusPhase) {
        if let completionSignal {
            completionSignal(phase)
            return
        }
        let sound = phase == .work ? workChime : breakChime
        if sound?.play() != true { NSSound.beep() }
        NSApp?.requestUserAttention(.criticalRequest)
    }

    private func updateDockBadge(synchronizeNotification: Bool = true) {
        if synchronizeNotification {
            notifications?.synchronize(clock: data.clock, enabled: data.notificationsEnabled, at: now)
        }
        guard managesDockBadge else { return }
        switch data.clock.phase {
        case .breakReady: NSApp?.dockTile.badgeLabel = "Break"
        case .ready: NSApp?.dockTile.badgeLabel = "Ready"
        case .work, .breakTime: NSApp?.dockTile.badgeLabel = nil
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        if enabled, let notifications {
            do {
                guard try await notifications.requestAuthorization() else {
                    errorMessage = "Notifications are disabled for Planador. Enable them in System Settings → Notifications."
                    return
                }
            } catch {
                errorMessage = "Notifications could not be enabled: \(error.localizedDescription)"
                return
            }
        }
        data.notificationsEnabled = enabled
        updateDockBadge()
        save()
    }

    /// Export a paused snapshot, including the elapsed portion of any running session.
    func backupData(at date: Date = Date()) throws -> Data {
        try encode(backupSnapshot(at: date))
    }

    private func backupSnapshot(at date: Date) -> AppData {
        var snapshot = data
        if let start = snapshot.clock.startedAt {
            let end = min(date, start.addingTimeInterval(snapshot.clock.remaining(at: start)))
            if snapshot.clock.phase == .work, end > start {
                snapshot.sessions.append(FocusSession(taskID: snapshot.clock.taskID, startedAt: start, endedAt: end))
            }
            snapshot.clock.elapsedBeforeRun = snapshot.clock.elapsed(at: date)
            snapshot.clock.startedAt = nil
            if snapshot.clock.remaining(at: date) == 0 {
                let wasWork = snapshot.clock.phase == .work
                snapshot.clock.phase = wasWork ? .breakReady : .ready
                snapshot.clock.durationMinutes = wasWork ? snapshot.timerSettings.breakMinutes : snapshot.timerSettings.workMinutes
                snapshot.clock.elapsedBeforeRun = 0
            }
        }
        return snapshot
    }

    func readBackup(_ bytes: Data) throws -> AppData {
        let restored = try JSONDecoder().decode(AppData.self, from: bytes)
        try validateBackup(restored)
        return restored
    }

    private func validateBackup(_ restored: AppData) throws {
        guard Set(restored.tasks.map(\.id)).count == restored.tasks.count,
              Set(restored.sessions.map(\.id)).count == restored.sessions.count,
              restored.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              (1...120).contains(restored.timerSettings.workMinutes),
              (1...30).contains(restored.timerSettings.breakMinutes),
              (1...120).contains(restored.clock.durationMinutes),
              restored.clock.elapsedBeforeRun.isFinite,
              (0...Double(restored.clock.durationMinutes * 60)).contains(restored.clock.elapsedBeforeRun),
              restored.sessions.allSatisfy({ $0.startedAt <= $0.endedAt }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    /// Preserve a recovery copy before replacing the live file. Neither write changes memory on failure.
    @discardableResult
    func restoreBackup(_ restored: AppData) throws -> URL {
        try validateBackup(restored)
        guard maySave else { throw CocoaError(.fileWriteNoPermission) }
        var replacement = restored
        replacement.clock.startedAt = nil
        // Notification preferences belong to this Mac, not the imported backup.
        replacement.notificationsEnabled = data.notificationsEnabled
        if let id = replacement.clock.taskID,
           !replacement.tasks.contains(where: { $0.id == id && $0.completedAt == nil }) {
            replacement.clock.taskID = nil
        }
        if replacement.clock.elapsedBeforeRun >= Double(replacement.clock.durationMinutes * 60) {
            let wasWork = replacement.clock.phase == .work
            replacement.clock.phase = wasWork ? .breakReady : .ready
            replacement.clock.durationMinutes = wasWork ? replacement.timerSettings.breakMinutes : replacement.timerSettings.workMinutes
            replacement.clock.elapsedBeforeRun = 0
        }
        let recoveryURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("before-restore-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try backupData().write(to: recoveryURL, options: .atomic)
        try encode(replacement).write(to: fileURL, options: .atomic)
        data = replacement
        now = Date()
        undoManager?.removeAllActions()
        updateDockBadge()
        return recoveryURL
    }

    private func encode(_ value: AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func save() {
        guard maySave else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try encode(data).write(to: fileURL, options: .atomic)
        } catch {
            errorMessage = "Your changes could not be saved: \(error.localizedDescription)"
        }
    }
}
