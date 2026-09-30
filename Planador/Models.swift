import Foundation

struct PlanTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var estimatedMinutes: Int
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

struct FocusClock: Codable {
    var taskID: UUID?
    var durationMinutes: Int = 25
    var elapsedBeforeRun: TimeInterval = 0
    var startedAt: Date?

    func elapsed(at date: Date) -> TimeInterval {
        min(TimeInterval(durationMinutes * 60), elapsedBeforeRun +
            (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0))
    }

    func remaining(at date: Date) -> TimeInterval {
        max(0, TimeInterval(durationMinutes * 60) - elapsed(at: date))
    }
}

struct AppData: Codable {
    var tasks: [PlanTask] = []
    var sessions: [FocusSession] = []
    var clock: FocusClock = FocusClock()
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

