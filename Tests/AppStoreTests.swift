import XCTest
@testable import Planador

final class AppStoreTests: XCTestCase {
    @MainActor
    func testTaskLifecyclePersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let store = AppStore(fileURL: file)

        store.addTask(title: "  Fix the build  ", estimatedMinutes: 45, notes: "Check CI", toToday: false)
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
        store.addTask(title: "First", estimatedMinutes: 25, notes: "", toToday: true)
        store.addTask(title: "Second", estimatedMinutes: 25, notes: "", toToday: true)
        store.addTask(title: "Backlog", estimatedMinutes: 25, notes: "", toToday: false)
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
}
