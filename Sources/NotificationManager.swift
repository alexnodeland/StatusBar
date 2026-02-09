// NotificationManager.swift
// macOS notification delivery and permission handling.

import SwiftUI
import UserNotifications

// MARK: - Notification Manager

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @AppStorage("notificationsEnabled") var notificationsEnabled = true

    private override init() {
        super.init()
        // Set delegate and categories immediately — these don't require NSApp
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                DispatchQueue.main.async {
                    NSApp?.activate(ignoringOtherApps: true)
                }
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    private func registerCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW",
            title: "View Details",
            options: .foreground
        )
        let category = UNNotificationCategory(
            identifier: "STATUS_CHANGE",
            actions: [viewAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func sendStatusChange(source: String, url: String, title: String, body: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "STATUS_CHANGE"
        content.userInfo = ["source": source, "url": url]

        let request = UNNotificationRequest(
            identifier: "\(source)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
