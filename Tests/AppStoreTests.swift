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
