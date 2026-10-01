import AppKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published private(set) var now = Date()
    @Published var errorMessage: String?

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

    var todayTasks: [PlanTask] {
        data.tasks.filter { $0.completedAt == nil && $0.plannedDate.map { calendar.isDate($0, inSameDayAs: today) } == true }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var backlogTasks: [PlanTask] {
        data.tasks.filter { $0.completedAt == nil && $0.plannedDate == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var focusableTasks: [PlanTask] { todayTasks + backlogTasks }

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
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let order = (data.tasks.map(\.sortOrder).max() ?? -1) + 1
        data.tasks.append(PlanTask(title: cleanTitle, notes: notes,
                                   plannedDate: toToday ? today : nil, sortOrder: order))
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
        guard let index = data.tasks.firstIndex(where: { $0.id == id && $0.completedAt == nil }) else { return }
        if data.clock.taskID == id {
            changeFocusedTask(to: nextTaskID(after: id), at: Date())
        }
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
        if data.clock.taskID == id {
            changeFocusedTask(to: nextTaskID(after: id), at: Date())
        }
        data.tasks.removeAll { $0.id == id }
        save()
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
            guard selectedTask?.completedAt == nil else { return }
            data.clock.phase = .work
            data.clock.durationMinutes = data.timerSettings.workMinutes
            data.clock.elapsedBeforeRun = 0
        } else if data.clock.phase == .work {
            guard selectedTask?.completedAt == nil || data.clock.elapsedBeforeRun > 0 else { return }
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
        save()
    }

    func resetTimer() {
        pauseTimer()
        data.clock.elapsedBeforeRun = 0
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
            updateDockBadge()
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

    private func updateDockBadge() {
        guard managesDockBadge else { return }
        switch data.clock.phase {
        case .breakReady: NSApp?.dockTile.badgeLabel = "Break"
        case .ready: NSApp?.dockTile.badgeLabel = "Ready"
        case .work, .breakTime: NSApp?.dockTile.badgeLabel = nil
        }
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
