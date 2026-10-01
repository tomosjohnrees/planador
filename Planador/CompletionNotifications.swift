import Foundation
import UserNotifications

@MainActor
final class CompletionNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "planador-timer-completion"

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }

    func synchronize(clock: FocusClock, enabled: Bool, at date: Date) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled, clock.startedAt != nil,
              clock.phase == .work || clock.phase == .breakTime,
              clock.remaining(at: date) > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = clock.phase == .work ? "Time to pause" : "Break complete"
        content.body = clock.phase == .work ? "Your focus session is complete. Take a break when you're ready." :
            "Your next focus session is ready when you are."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, clock.remaining(at: date)), repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
