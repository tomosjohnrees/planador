import XCTest
@testable import Planador

final class AppStoreTests: XCTestCase {
    @MainActor
    func testTaskLifecyclePersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let store = AppStore(fileURL: file)

        store.addTask(title: "  Fix the build  ", notes: "Check CI", toToday: false)
        let task = try XCTUnwrap(store.backlogTasks.first)
        XCTAssertEqual(task.title, "Fix the build")
        XCTAssertEqual(task.notes, "Check CI")

        store.move(task.id, to: store.today)
        XCTAssertEqual(store.todayTasks.map(\.id), [task.id])
        store.complete(task.id)
        XCTAssertEqual(store.completedToday.map(\.id), [task.id])

        let reloaded = AppStore(fileURL: file)
        XCTAssertEqual(reloaded.completedToday.map(\.id), [task.id])
        reloaded.reopen(task.id)
        XCTAssertEqual(reloaded.todayTasks.map(\.id), [task.id])
        reloaded.delete(task.id)
        XCTAssertTrue(reloaded.data.tasks.isEmpty)
    }

    @MainActor
    func testDeletingCompletedTaskKeepsLoggedFocusTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("data.json")
        let now = Date()
        let task = PlanTask(title: "Finished task", notes: "Context",
                            completedAt: now, sortOrder: 0)
        let session = FocusSession(taskID: task.id, startedAt: now.addingTimeInterval(-60),
                                   endedAt: now)
        try JSONEncoder().encode(AppData(tasks: [task], sessions: [session])).write(to: file)
        let store = AppStore(fileURL: file)
        let focusedBefore = store.focusedToday

        store.delete(task.id)
        XCTAssertTrue(store.completedToday.isEmpty)
        XCTAssertTrue(store.data.tasks.isEmpty)
        XCTAssertEqual(store.focusedToday, focusedBefore, accuracy: 0.01)

        let reloaded = AppStore(fileURL: file)
        XCTAssertTrue(reloaded.data.tasks.isEmpty)
        XCTAssertEqual(reloaded.focusedToday, focusedBefore, accuracy: 0.01)
    }

    @MainActor
    func testReorderingOnlyChangesSiblings() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = AppStore(fileURL: file)
        store.addTask(title: "First", notes: "", toToday: true)
        store.addTask(title: "Second", notes: "", toToday: true)
        store.addTask(title: "Backlog", notes: "", toToday: false)
        let second = try XCTUnwrap(store.todayTasks.last)

        store.moveWithinList(second.id, by: -1)
        XCTAssertEqual(store.todayTasks.map(\.title), ["Second", "First"])
        XCTAssertEqual(store.backlogTasks.map(\.title), ["Backlog"])
    }

    @MainActor
    func testCompletingTasksKeepsTheFocusTimerAndSelectsTheNextTask() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("data.json")
        let first = PlanTask(title: "First", plannedDate: Date(), sortOrder: 0)
        let second = PlanTask(title: "Second", plannedDate: Date(), sortOrder: 1)
        let start = Date().addingTimeInterval(-10)
        let data = AppData(tasks: [first, second],
                           clock: FocusClock(taskID: first.id, durationMinutes: 1,
                                             startedAt: start))
        try JSONEncoder().encode(data).write(to: file)
        let store = AppStore(fileURL: file)
        let remainingBefore = store.data.clock.remaining(at: Date())

        store.complete(first.id)
        XCTAssertEqual(store.selectedTask?.id, second.id)
        XCTAssertEqual(store.data.clock.phase, .work)
        XCTAssertNotNil(store.data.clock.startedAt)
        XCTAssertEqual(store.data.clock.remaining(at: Date()), remainingBefore, accuracy: 1)
        XCTAssertEqual(store.data.sessions.map(\.taskID), [first.id])

        store.complete(second.id)
        XCTAssertNil(store.selectedTask)
        XCTAssertNil(store.data.clock.taskID)
        XCTAssertNotNil(store.data.clock.startedAt)
        XCTAssertEqual(store.data.clock.phase, .work)

        store.pauseTimer()
        XCTAssertNil(store.data.clock.startedAt)
        store.startTimer()
        XCTAssertNotNil(store.data.clock.startedAt)

        let reloaded = AppStore(fileURL: file)
        XCTAssertNil(reloaded.data.clock.taskID)
        XCTAssertNotNil(reloaded.data.clock.startedAt)

        let currentStart = try XCTUnwrap(store.data.clock.startedAt)
        let remaining = store.data.clock.remaining(at: currentStart)
        store.updateClock(at: currentStart.addingTimeInterval(remaining))
        XCTAssertEqual(store.data.clock.phase, .breakReady)
        XCTAssertEqual(store.data.sessions.last?.taskID, nil)
        XCTAssertEqual(store.data.sessions.reduce(0) { $0 + $1.duration }, 60, accuracy: 1)
    }

    @MainActor
    func testChangingTasksManuallyPreservesTheFocusTimer() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("data.json")
        let first = PlanTask(title: "First", plannedDate: Date(), sortOrder: 0)
        let second = PlanTask(title: "Second", plannedDate: Date(), sortOrder: 1)
        let data = AppData(tasks: [first, second],
                           clock: FocusClock(taskID: first.id, durationMinutes: 25,
                                             startedAt: Date().addingTimeInterval(-10)))
        try JSONEncoder().encode(data).write(to: file)
        let store = AppStore(fileURL: file)
        let remainingBefore = store.data.clock.remaining(at: Date())

        store.selectForFocus(second.id)
        XCTAssertEqual(store.selectedTask?.id, second.id)
        XCTAssertNotNil(store.data.clock.startedAt)
        XCTAssertEqual(store.data.clock.remaining(at: Date()), remainingBefore, accuracy: 1)
        XCTAssertEqual(store.data.sessions.map(\.taskID), [first.id])
    }

    func testFocusClockCapsElapsedTime() {
        let start = Date(timeIntervalSince1970: 1000)
        let clock = FocusClock(taskID: UUID(), durationMinutes: 25,
                               elapsedBeforeRun: 60, startedAt: start)
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(30)), 1410)
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(1800)), 0)
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(1800)), 1500)
    }

    @MainActor
    func testWorkStopsUntilBreakIsStartedAndNextSessionWaits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("data.json")
        let task = PlanTask(title: "Implement feature", plannedDate: Date(), sortOrder: 0)
        let start = Date().addingTimeInterval(30)
        let saved = AppData(tasks: [task], clock: FocusClock(taskID: task.id, durationMinutes: 1,
                                                             startedAt: start),
                            timerSettings: TimerSettings(workMinutes: 1, breakMinutes: 1))
        try JSONEncoder().encode(saved).write(to: file)
        var signals: [FocusPhase] = []
        let store = AppStore(fileURL: file, completionSignal: { signals.append($0) })

        store.updateClock(at: start.addingTimeInterval(60), announce: true)
        XCTAssertEqual(store.data.clock.phase, .breakReady)
        XCTAssertNil(store.data.clock.startedAt)
        XCTAssertEqual(store.data.sessions.count, 1)
        XCTAssertEqual(store.data.sessions[0].duration, 60, accuracy: 0.001)
        XCTAssertEqual(signals, [.work])

        store.updateClock(at: start.addingTimeInterval(120), announce: true)
        XCTAssertEqual(store.data.clock.phase, .breakReady)
        XCTAssertEqual(signals, [.work])

        let breakStart = start.addingTimeInterval(120)
        store.startBreak(at: breakStart)
        XCTAssertEqual(store.data.clock.phase, .breakTime)
        XCTAssertEqual(store.data.clock.startedAt, breakStart)
        store.updateClock(at: breakStart.addingTimeInterval(60), announce: true)
        XCTAssertEqual(store.data.clock.phase, .ready)
        XCTAssertNil(store.data.clock.startedAt)
        XCTAssertEqual(store.data.sessions.count, 1)
        XCTAssertEqual(signals, [.work, .breakTime])

        store.startTimer()
        XCTAssertEqual(store.data.clock.phase, .work)
        XCTAssertNotNil(store.data.clock.startedAt)
    }

    func testCompletionChimesAreBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "FocusComplete", withExtension: "wav"))
        XCTAssertNotNil(Bundle.main.url(forResource: "BreakComplete", withExtension: "wav"))
    }

    @MainActor
    func testBreakCanBeSkippedAfterWorkStops() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("data.json")
        let data = AppData(clock: FocusClock(phase: .breakReady, durationMinutes: 5))
        try JSONEncoder().encode(data).write(to: file)
        let store = AppStore(fileURL: file)

        store.skipBreak()
        XCTAssertEqual(store.data.clock.phase, .ready)
        XCTAssertNil(store.data.clock.startedAt)
    }

    @MainActor
    func testNotesRemainAvailableOnEarlierCompletedTasks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("data.json")
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let task = PlanTask(title: "Finished task", notes: "Original context",
                            completedAt: yesterday, sortOrder: 0)
        try JSONEncoder().encode(AppData(tasks: [task])).write(to: file)

        let store = AppStore(fileURL: file)
        XCTAssertEqual(store.completedEarlier.map(\.id), [task.id])
        store.updateNotes("Revised context", for: task.id)
        let reloaded = AppStore(fileURL: file)
        XCTAssertEqual(reloaded.completedEarlier.first?.notes, "Revised context")
    }

    @MainActor
    func testLegacyDataKeepsTasksAndFocusLength() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("data.json")
        let task = PlanTask(title: "Existing task", sortOrder: 0)
        let current = AppData(tasks: [task], clock: FocusClock(durationMinutes: 45))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        json.removeValue(forKey: "timerSettings")
        var oldClock = try XCTUnwrap(json["clock"] as? [String: Any])
        oldClock.removeValue(forKey: "phase")
        json["clock"] = oldClock
        var oldTasks = try XCTUnwrap(json["tasks"] as? [[String: Any]])
        oldTasks[0]["estimatedMinutes"] = 90
        json["tasks"] = oldTasks
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        let store = AppStore(fileURL: file)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.backlogTasks.map(\.title), ["Existing task"])
        XCTAssertEqual(store.data.timerSettings.workMinutes, 45)
        XCTAssertEqual(store.data.timerSettings.breakMinutes, 5)
    }
}

final class PlanningAndBackupTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("data.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func write(_ data: AppData) throws { try JSONEncoder().encode(data).write(to: file) }

    @MainActor
    func testEveryIncompleteTaskRemainsVisibleAcrossMidnight() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: today))
        let tasks = [PlanTask(title: "Overdue", plannedDate: yesterday, sortOrder: 0),
                     PlanTask(title: "Today", plannedDate: today, sortOrder: 1),
                     PlanTask(title: "Tomorrow", plannedDate: tomorrow, sortOrder: 2),
                     PlanTask(title: "Later", plannedDate: later, sortOrder: 3),
                     PlanTask(title: "Backlog", sortOrder: 4)]
        try write(AppData(tasks: tasks))
        let store = AppStore(fileURL: file)
        store.updateClock(at: today.addingTimeInterval(12 * 3600))
        XCTAssertEqual(store.carriedOverTasks.map(\.title), ["Overdue"])
        XCTAssertEqual(store.tomorrowTasks.map(\.title), ["Tomorrow"])
        XCTAssertEqual(store.upcomingDates, [later])
        store.updateClock(at: tomorrow)
        XCTAssertEqual(store.carriedOverTasks.map(\.title), ["Overdue", "Today"])
        XCTAssertEqual(store.todayTasks.map(\.title), ["Tomorrow"])
        let visible = store.carriedOverTasks + store.todayTasks + store.tomorrowTasks + store.backlogTasks +
            store.upcomingDates.flatMap { store.tasks(on: $0) }
        XCTAssertEqual(Set(visible.map(\.id)), Set(tasks.map(\.id)))
        XCTAssertEqual(visible.count, tasks.count)
        XCTAssertTrue(store.focusableTasks.contains(where: { $0.title == "Overdue" }))
    }

    @MainActor
    func testDatesAreGroupedByCalendarDayAndDropsReorderOnlyTheirDestination() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let first = PlanTask(title: "First", plannedDate: today.addingTimeInterval(3600), sortOrder: 5)
        let second = PlanTask(title: "Second", plannedDate: today.addingTimeInterval(7200), sortOrder: 10)
        let backlog = PlanTask(title: "Backlog", sortOrder: 15)
        let other = PlanTask(title: "Other day", plannedDate: today.addingTimeInterval(3 * 86400), sortOrder: 20)
        try write(AppData(tasks: [first, second, backlog, other]))
        let store = AppStore(fileURL: file)
        XCTAssertEqual(store.todayTasks.count, 2)
        store.moveWithinList(second.id, by: -1)
        XCTAssertEqual(store.todayTasks.map(\.id), [second.id, first.id])
        XCTAssertTrue(store.acceptTaskDrop(["planador-task:\(backlog.id)"], on: today, before: first.id))
        XCTAssertEqual(store.todayTasks.map(\.id), [second.id, backlog.id, first.id])
        XCTAssertEqual(store.data.tasks.first(where: { $0.id == other.id }), other)
        store.move(backlog.id, to: store.tomorrow.addingTimeInterval(3600))
        XCTAssertEqual(store.tomorrowTasks.map(\.id), [backlog.id])
        XCTAssertEqual(store.tomorrowTasks.first?.plannedDate, store.tomorrow)
        store.move(backlog.id, to: nil)
        XCTAssertEqual(store.backlogTasks.map(\.id), [backlog.id])
    }

    @MainActor
    func testInvalidDropsCannotChangeTasks() throws {
        let task = PlanTask(title: "Active", sortOrder: 0)
        let complete = PlanTask(title: "Done", completedAt: Date(), sortOrder: 1)
        try write(AppData(tasks: [task, complete]))
        let store = AppStore(fileURL: file)
        XCTAssertFalse(store.acceptTaskDrop([task.id.uuidString], on: store.today))
        XCTAssertFalse(store.acceptTaskDrop(["planador-task:\(UUID())"], on: store.today))
        XCTAssertFalse(store.acceptTaskDrop(["planador-task:\(complete.id)"], on: store.today))
        XCTAssertFalse(store.acceptTaskDrop(["planador-task:\(task.id)", "planador-task:\(task.id)"], on: store.today))
        XCTAssertFalse(store.placeTask(task.id, on: store.today, before: UUID()))
        XCTAssertFalse(store.placeTask(task.id, on: nil, before: task.id))
        XCTAssertEqual(store.data.tasks, [task, complete])
    }

    @MainActor
    func testMovingTheFocusedTaskToTheFuturePreservesTimerAndLoggedTime() throws {
        let now = Date()
        let first = PlanTask(title: "First", plannedDate: now, sortOrder: 0)
        let second = PlanTask(title: "Second", plannedDate: now, sortOrder: 1)
        try write(AppData(tasks: [first, second],
                          clock: FocusClock(taskID: first.id, startedAt: now.addingTimeInterval(-10))))
        let store = AppStore(fileURL: file)
        let remaining = store.data.clock.remaining(at: Date())
        store.move(first.id, to: store.tomorrow)
        XCTAssertEqual(store.selectedTask?.id, second.id)
        XCTAssertNotNil(store.data.clock.startedAt)
        XCTAssertEqual(store.data.clock.remaining(at: Date()), remaining, accuracy: 1)
        XCTAssertEqual(store.data.sessions.map(\.taskID), [first.id])
        XCTAssertEqual(store.tomorrowTasks.map(\.id), [first.id])
    }

    @MainActor
    func testUndoRedoTaskChangesPersistsWithoutRewindingTheTimer() throws {
        let now = Date()
        let task = PlanTask(title: "Original", notes: "Keep me", plannedDate: now, sortOrder: 0)
        let session = FocusSession(taskID: task.id, startedAt: now.addingTimeInterval(-120), endedAt: now.addingTimeInterval(-60))
        try write(AppData(tasks: [task], sessions: [session], clock: FocusClock(taskID: task.id, startedAt: now.addingTimeInterval(-10))))
        let store = AppStore(fileURL: file)
        let manager = UndoManager()
        manager.groupsByEvent = false
        store.undoManager = manager
        manager.beginUndoGrouping()
        store.renameTask(task.id, to: "Renamed")
        manager.endUndoGrouping()
        manager.undo()
        XCTAssertEqual(store.data.tasks.first?.title, "Original")
        manager.redo()
        XCTAssertEqual(store.data.tasks.first?.title, "Renamed")
        manager.beginUndoGrouping()
        store.delete(task.id)
        manager.endUndoGrouping()
        let sessionIDs = store.data.sessions.map(\.id)
        let remaining = store.data.clock.remaining(at: Date())
        manager.undo()
        XCTAssertEqual(store.data.tasks.first?.notes, "Keep me")
        XCTAssertEqual(store.data.sessions.map(\.id), sessionIDs)
        XCTAssertEqual(store.data.clock.remaining(at: Date()), remaining, accuracy: 1)
        XCTAssertNotNil(store.data.clock.startedAt)
        XCTAssertEqual(AppStore(fileURL: file).data.tasks.first?.title, "Renamed")
        manager.redo()
        XCTAssertTrue(store.data.tasks.isEmpty)
        XCTAssertEqual(store.data.sessions.map(\.id), sessionIDs)
    }

    @MainActor
    func testUndoSchedulingCompletionNotesAndAdding() throws {
        let store = AppStore(fileURL: file)
        let manager = UndoManager()
        manager.groupsByEvent = false
        store.undoManager = manager
        func action(_ change: () -> Void) { manager.beginUndoGrouping(); change(); manager.endUndoGrouping() }
        action { store.addTask(title: "Task", notes: "Original", toToday: true) }
        let task = try XCTUnwrap(store.todayTasks.first)
        action { store.updateNotes("Changed", for: task.id) }
        manager.undo()
        XCTAssertEqual(store.todayTasks.first?.notes, "Original")
        action { store.move(task.id, to: store.tomorrow) }
        manager.undo()
        XCTAssertEqual(store.todayTasks.map(\.id), [task.id])
        action { store.complete(task.id) }
        manager.undo()
        XCTAssertEqual(store.todayTasks.map(\.id), [task.id])
        manager.undo()
        XCTAssertTrue(store.data.tasks.isEmpty)
    }

    @MainActor
    func testSearchIncludesNotesAndEveryTaskStatus() throws {
        let now = Date()
        let later = now.addingTimeInterval(7 * 86400)
        let tasks = [PlanTask(title: "Café launch", notes: "Billing fixes", sortOrder: 0),
                     PlanTask(title: "Future", notes: "cafe BILLING", plannedDate: later, sortOrder: 1),
                     PlanTask(title: "Completed", notes: "Cafe billing", completedAt: now, sortOrder: 2),
                     PlanTask(title: "Unrelated", sortOrder: 3)]
        try write(AppData(tasks: tasks))
        let store = AppStore(fileURL: file)
        XCTAssertEqual(store.searchTasks("  cafe  billing \n").map(\.id), Array(tasks.prefix(3)).map(\.id))
        XCTAssertTrue(store.searchTasks(" ").isEmpty)
        XCTAssertTrue(store.searchTasks("missing").isEmpty)
        XCTAssertEqual(store.searchTasks("future").map(\.id), [tasks[1].id])
    }

    @MainActor
    func testBackupCapturesRunningTimeWithoutChangingTheLiveTimer() throws {
        let start = Date().addingTimeInterval(60)
        let task = PlanTask(title: "Working", plannedDate: Date(), sortOrder: 0)
        let clock = FocusClock(taskID: task.id, elapsedBeforeRun: 30, startedAt: start)
        let logged = FocusSession(taskID: task.id, startedAt: start.addingTimeInterval(-30), endedAt: start)
        try write(AppData(tasks: [task], sessions: [logged], clock: clock))
        let store = AppStore(fileURL: file)
        let bytes = try store.backupData(at: start.addingTimeInterval(15))
        let backup = try store.readBackup(bytes)
        XCTAssertNil(backup.clock.startedAt)
        XCTAssertEqual(backup.clock.elapsedBeforeRun, 45)
        XCTAssertEqual(backup.sessions.reduce(0) { $0 + $1.duration }, 45)
        XCTAssertEqual(store.data.clock.startedAt, start)
        XCTAssertEqual(store.data.sessions.count, 1)
        XCTAssertEqual(store.data.clock.elapsedBeforeRun, 30)
        let recovery = try store.restoreBackup(backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.path))
        XCTAssertNil(store.data.clock.startedAt)
        XCTAssertEqual(store.data.sessions.reduce(0) { $0 + $1.duration }, 45)
    }

    @MainActor
    func testBackupAtTimerEndDoesNotDoubleCountAndPreparesTheBreak() throws {
        let start = Date().addingTimeInterval(60)
        let clock = FocusClock(durationMinutes: 1, startedAt: start)
        try write(AppData(clock: clock))
        let store = AppStore(fileURL: file)
        let backup = try store.readBackup(store.backupData(at: start.addingTimeInterval(120)))
        XCTAssertEqual(backup.clock.phase, .breakReady)
        XCTAssertNil(backup.clock.startedAt)
        XCTAssertEqual(backup.clock.elapsedBeforeRun, 0)
        XCTAssertEqual(backup.sessions.reduce(0) { $0 + $1.duration }, 60)
    }

    @MainActor
    func testRestoreKeepsRecoveryCopyAndSettingsAndClearsUndo() throws {
        let original = PlanTask(title: "Original", notes: "Original notes", sortOrder: 0)
        try write(AppData(tasks: [original], notificationsEnabled: false))
        let store = AppStore(fileURL: file)
        let manager = UndoManager()
        store.undoManager = manager
        manager.beginUndoGrouping()
        store.renameTask(original.id, to: "Before restore")
        manager.endUndoGrouping()
        let replacement = PlanTask(title: "Imported", notes: "Imported notes", sortOrder: 0)
        let recoveryURL = try store.restoreBackup(AppData(tasks: [replacement], notificationsEnabled: true))
        XCTAssertEqual(store.data.tasks, [replacement])
        XCTAssertFalse(store.data.notificationsEnabled)
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        let recovery = try store.readBackup(Data(contentsOf: recoveryURL))
        XCTAssertEqual(recovery.tasks.first?.title, "Before restore")
        XCTAssertEqual(recovery.tasks.first?.notes, "Original notes")
        XCTAssertEqual(AppStore(fileURL: file).data.tasks, [replacement])
    }

    @MainActor
    func testInvalidBackupCannotReplaceCurrentData() throws {
        let task = PlanTask(title: "Keep me", sortOrder: 0)
        try write(AppData(tasks: [task]))
        let store = AppStore(fileURL: file)
        let diskBefore = try Data(contentsOf: file)
        XCTAssertThrowsError(try store.readBackup(Data("not json".utf8)))
        let duplicate = AppData(tasks: [task, task])
        XCTAssertThrowsError(try store.readBackup(JSONEncoder().encode(duplicate)))
        XCTAssertThrowsError(try store.restoreBackup(duplicate))
        XCTAssertThrowsError(try store.restoreBackup(AppData(timerSettings: TimerSettings(workMinutes: 999, breakMinutes: 5))))
        XCTAssertThrowsError(try store.restoreBackup(AppData(sessions: [FocusSession(startedAt: Date(), endedAt: .distantPast)])))
        XCTAssertEqual(store.data.tasks, [task])
        XCTAssertEqual(try Data(contentsOf: file), diskBefore)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["data.json"])
    }

    @MainActor
    func testRestoreWriteFailureKeepsMemoryIntact() throws {
        let task = PlanTask(title: "Original", sortOrder: 0)
        try write(AppData(tasks: [task]))
        let store = AppStore(fileURL: file)
        try FileManager.default.removeItem(at: directory)
        try Data("blocking file".utf8).write(to: directory)
        XCTAssertThrowsError(try store.restoreBackup(AppData()))
        XCTAssertEqual(store.data.tasks, [task])
    }

    @MainActor
    func testFocusingFutureTaskMovesItToTodayAndEmptyTimerCannotStart() throws {
        let store = AppStore(fileURL: file)
        XCTAssertFalse(store.canStartTimer)
        store.startTimer()
        XCTAssertNil(store.data.clock.startedAt)
        store.addTask(title: "Future", notes: "", plannedDate: store.dayAfterTomorrow)
        let task = try XCTUnwrap(store.data.tasks.first)
        store.focusTask(task.id)
        XCTAssertEqual(store.todayTasks.map(\.id), [task.id])
        XCTAssertEqual(store.section, .focus)
        XCTAssertTrue(store.canStartTimer)
        store.toggleTimer()
        XCTAssertNotNil(store.data.clock.startedAt)
        store.toggleTimer()
        XCTAssertNil(store.data.clock.startedAt)
    }

    func testMalformedTimerDurationsAndElapsedTimeAreRejected() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(FocusClock())) as? [String: Any])
        for duration in [0, -1, Int.max] {
            object["durationMinutes"] = duration
            XCTAssertThrowsError(try JSONDecoder().decode(FocusClock.self, from: JSONSerialization.data(withJSONObject: object)))
        }
        object["durationMinutes"] = 25
        for elapsed in [-1, 1501] {
            object["elapsedBeforeRun"] = elapsed
            XCTAssertThrowsError(try JSONDecoder().decode(FocusClock.self, from: JSONSerialization.data(withJSONObject: object)))
        }
    }

    @MainActor
    func testBackupFilenameUsesTheLocalCalendarDay() throws {
        let store = AppStore(fileURL: file)
        let date = Calendar.current.startOfDay(for: Date())
        store.updateClock(at: date)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let expected = String(format: "Planador-%04d-%02d-%02d", components.year!, components.month!, components.day!)
        XCTAssertEqual(store.backupFilename, expected)
    }
}

final class TaskDragTests: XCTestCase {
    func testNativeDragExportsOnlyTheTextPayloadAndLoadsLosslessly() async throws {
        let id = UUID()
        let provider = TaskDrag.itemProvider(for: id)
        XCTAssertEqual(provider.registeredTypeIdentifiers, [TaskDrag.typeIdentifier])
        let bytes: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: TaskDrag.typeIdentifier) { bytes, error in
                if let error { continuation.resume(throwing: error) }
                else if let bytes { continuation.resume(returning: bytes) }
                else { continuation.resume(throwing: CocoaError(.fileReadCorruptFile)) }
            }
        }
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "planador-task:\(id.uuidString)")
    }
}
