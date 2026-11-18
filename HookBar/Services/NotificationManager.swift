import Foundation
import UserNotifications

/// Bannières macOS pour les nouveaux messages des salons où elles sont activées.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var center: UNUserNotificationCenter { .current() }

    func start() {
        center.delegate = self
    }

    /// Demande l'autorisation (la première fois seulement, macOS ne redemande pas ensuite).
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(message: StoredMessage, channelName: String) {
        let content = UNMutableNotificationContent()
        content.title = "#\(channelName)"
        content.subtitle = message.headline
        content.body = String(message.preview.prefix(240))
        content.sound = .default
        content.threadIdentifier = message.channelId
        center.add(UNNotificationRequest(identifier: message.id, content: content, trigger: nil))
    }

    /// Une seule bannière quand beaucoup de messages arrivent d'un coup (rattrapage après une coupure).
    func postSummary(count: Int, channelId: String, channelName: String) {
        let content = UNMutableNotificationContent()
        content.title = "#\(channelName)"
        content.body = String(localized: "\(count) nouveaux messages")
        content.sound = .default
        content.threadIdentifier = channelId
        center.add(UNNotificationRequest(identifier: "summary-\(channelId)-\(UUID().uuidString)", content: content, trigger: nil))
    }

    func remove(messageIds: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: messageIds)
    }

    // L'app est toujours « au premier plan » pour macOS (barre de menus) : afficher quand même la bannière.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
