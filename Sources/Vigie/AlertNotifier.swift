import Foundation
import UserNotifications

/// Notifications macOS pour les alertes importantes. N'envoie rien en dehors de ce Mac.
enum AlertNotifier {
    /// Les notifications n'existent que pour une vraie app (.app), pas pour un exécutable lancé « nu ».
    static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, id: String) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "\(id)#\(UUID().uuidString)", content: content, trigger: nil))
        }
    }
}
