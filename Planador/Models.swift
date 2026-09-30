import Foundation

struct PlanTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var plannedDate: Date?
    var completedAt: Date?
    var sortOrder: Int
    var createdAt: Date = Date()
}

struct FocusSession: Identifiable, Codable {
    var id: UUID = UUID()
    var taskID: UUID
    var startedAt: Date
    var endedAt: Date

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

enum FocusPhase: String, Codable {
    case work
    case breakTime
    case ready
}

struct TimerSettings: Codable {
    var workMinutes = 25
    var breakMinutes = 5
}

struct FocusClock: Codable {
    var taskID: UUID?
    var phase: FocusPhase
    var durationMinutes: Int
    var elapsedBeforeRun: TimeInterval
    var startedAt: Date?

    init(taskID: UUID? = nil, phase: FocusPhase = .work, durationMinutes: Int = 25,
         elapsedBeforeRun: TimeInterval = 0, startedAt: Date? = nil) {
        self.taskID = taskID
        self.phase = phase
        self.durationMinutes = durationMinutes
        self.elapsedBeforeRun = elapsedBeforeRun
        self.startedAt = startedAt
    }

    private enum CodingKeys: String, CodingKey {
        case taskID, phase, durationMinutes, elapsedBeforeRun, startedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try values.decodeIfPresent(UUID.self, forKey: .taskID)
        phase = try values.decodeIfPresent(FocusPhase.self, forKey: .phase) ?? .work
        durationMinutes = max(1, try values.decode(Int.self, forKey: .durationMinutes))
        elapsedBeforeRun = max(0, try values.decode(TimeInterval.self, forKey: .elapsedBeforeRun))
        startedAt = try values.decodeIfPresent(Date.self, forKey: .startedAt)
    }

    func elapsed(at date: Date) -> TimeInterval {
        max(0, min(TimeInterval(durationMinutes * 60), elapsedBeforeRun +
            (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0))
        )
    }

    func remaining(at date: Date) -> TimeInterval {
        max(0, TimeInterval(durationMinutes * 60) - elapsed(at: date))
    }
}

struct AppData: Codable {
    var tasks: [PlanTask]
    var sessions: [FocusSession]
    var clock: FocusClock
    var timerSettings: TimerSettings

    init(tasks: [PlanTask] = [], sessions: [FocusSession] = [],
         clock: FocusClock = FocusClock(), timerSettings: TimerSettings = TimerSettings()) {
        self.tasks = tasks
        self.sessions = sessions
        self.clock = clock
        self.timerSettings = timerSettings
    }

    private enum CodingKeys: String, CodingKey {
        case tasks, sessions, clock, timerSettings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try values.decode([PlanTask].self, forKey: .tasks)
        sessions = try values.decode([FocusSession].self, forKey: .sessions)
        clock = try values.decode(FocusClock.self, forKey: .clock)
        timerSettings = try values.decodeIfPresent(TimerSettings.self, forKey: .timerSettings)
            ?? TimerSettings(workMinutes: clock.durationMinutes, breakMinutes: 5)
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case focus = "Focus"
    case review = "Review"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .plan: "calendar"
        case .focus: "circle.dotted.circle"
        case .review: "chart.bar"
        }
    }
}
