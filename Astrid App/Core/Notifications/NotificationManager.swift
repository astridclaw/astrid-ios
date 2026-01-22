import Foundation
import UserNotifications

/// NotificationManager handles local notifications for task due dates
/// Integrates with ReminderSettings to schedule notifications based on user preferences
@MainActor
class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let settings = ReminderSettings.shared

    private init() {
        // Set delegate to handle notification taps
        center.delegate = NotificationDelegate.shared
    }

    // MARK: - Permission Management

    /// Request notification permissions from user
    func requestPermission() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        return granted
    }

    /// Check current notification permission status
    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Schedule Notifications

    /// Schedule notification for a task with due date/time
    /// - Parameters:
    ///   - task: Task to schedule notification for
    func scheduleNotification(for task: Task) async throws {
        // Only schedule if push notifications are enabled
        guard settings.pushEnabled else { return }

        // Check permission
        let status = await checkPermissionStatus()
        guard status == .authorized else {
            print("⚠️ Notification permission not granted, skipping notification for task \(task.id)")
            return
        }

        // Get the due date/time
        guard let dueDate = task.dueDateTime else {
            print("ℹ️ Task \(task.id) has no due date, skipping notification")
            return
        }

        // Calculate reminder time based on user settings
        let reminderOffset = settings.defaultReminderOffset
        let reminderDate = dueDate.addingTimeInterval(TimeInterval(-reminderOffset.rawValue * 60))

        // Don't schedule notifications in the past
        guard reminderDate > Date() else {
            print("⚠️ Reminder date is in the past for task \(task.id), skipping")
            return
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Task Due Soon"
        content.body = task.title
        content.sound = .default
        // Note: Badge count is managed by BadgeManager based on due/overdue tasks
        // Don't set badge here to avoid overriding the accurate count

        // Add task ID to userInfo for deep linking
        content.userInfo = [
            "taskId": task.id,
            "type": "task_reminder"
        ]

        // Add actions
        content.categoryIdentifier = "TASK_REMINDER"

        // Create trigger (date-based)
        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        // Create request with unique identifier (task ID)
        let request = UNNotificationRequest(
            identifier: "task_\(task.id)",
            content: content,
            trigger: trigger
        )

        // Schedule notification
        try await center.add(request)

        print("✅ Scheduled notification for task '\(task.title)' at \(reminderDate)")
    }

    /// Schedule notifications for multiple tasks
    func scheduleNotifications(for tasks: [Task]) async {
        for task in tasks {
            do {
                try await scheduleNotification(for: task)
            } catch {
                print("❌ Failed to schedule notification for task \(task.id): \(error)")
            }
        }
    }

    // MARK: - Cancel Notifications

    /// Cancel notification for a specific task
    func cancelNotification(for taskId: String) async {
        center.removePendingNotificationRequests(withIdentifiers: ["task_\(taskId)"])
        print("🗑️ Cancelled notification for task \(taskId)")
    }

    /// Cancel notifications for multiple tasks
    func cancelNotifications(for taskIds: [String]) async {
        let identifiers = taskIds.map { "task_\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        print("🗑️ Cancelled \(taskIds.count) notifications")
    }

    /// Cancel all pending notifications
    func cancelAllNotifications() async {
        center.removeAllPendingNotificationRequests()
        print("🗑️ Cancelled all pending notifications")
    }

    // MARK: - Snooze

    /// Snooze a notification for specified minutes
    func snoozeNotification(for task: Task, minutes: Int) async throws {
        // Cancel existing notification
        await cancelNotification(for: task.id)

        // Calculate new reminder time
        let snoozeDate = Date().addingTimeInterval(TimeInterval(minutes * 60))

        // Create temporary task with snoozed due date
        var snoozedTask = task
        snoozedTask.dueDateTime = snoozeDate
        snoozedTask.isAllDay = false  // Snoozed tasks have specific times

        // Schedule new notification
        try await scheduleNotification(for: snoozedTask)

        print("⏰ Snoozed task '\(task.title)' for \(minutes) minutes (until \(snoozeDate))")
    }

    // MARK: - Query Notifications

    /// Get all pending notification requests
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await center.pendingNotificationRequests()
    }

    /// Check if notification exists for task
    func hasNotification(for taskId: String) async -> Bool {
        let pending = await getPendingNotifications()
        return pending.contains { $0.identifier == "task_\(taskId)" }
    }

    // MARK: - Reschedule

    /// Reschedule notification when task due date changes
    func rescheduleNotification(for task: Task) async throws {
        await cancelNotification(for: task.id)
        try await scheduleNotification(for: task)
    }

    /// Reschedule all notifications (useful when settings change)
    func rescheduleAllNotifications(for tasks: [Task]) async {
        await cancelAllNotifications()
        await scheduleNotifications(for: tasks)
    }

    // MARK: - Test Reminder

    /// Schedule a test notification that fires in 5 seconds
    func scheduleTestReminder() async throws {
        // Check permission
        let status = await checkPermissionStatus()
        guard status == .authorized else {
            throw NotificationError.permissionDenied
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Test Reminder"
        content.body = "This is a test notification from Astrid"
        content.sound = .default
        // Note: Badge count is managed by BadgeManager based on due/overdue tasks
        // Don't set badge here to avoid overriding the accurate count

        // Add test identifier to userInfo
        content.userInfo = [
            "type": "test_reminder"
        ]

        // Create trigger (5 seconds from now)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)

        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: "test_reminder_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        // Schedule notification
        try await center.add(request)

        print("✅ Scheduled test notification (will fire in 5 seconds)")
    }
}

enum NotificationError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission not granted. Please enable notifications in Settings."
        }
    }
}

// MARK: - Notification Delegate

/// Handles notification taps and foreground presentation
@MainActor
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {
        super.init()
    }

    /// Handle notification tap (when app is in background/closed)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        print("🔔 [NotificationDelegate] Notification tapped!")
        print("🔔 [NotificationDelegate] Action identifier: \(response.actionIdentifier)")

        let userInfo = response.notification.request.content.userInfo
        print("🔔 [NotificationDelegate] UserInfo: \(userInfo)")

        // Extract task ID for deep linking
        if let taskId = userInfo["taskId"] as? String {
            print("📱 [NotificationDelegate] User tapped notification for task: \(taskId)")
            print("📱 [NotificationDelegate] Posting OpenTask notification to NotificationCenter")

            // Post notification for ReminderPresenter to catch
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenTask"),
                object: nil,
                userInfo: ["taskId": taskId]
            )
            print("✅ [NotificationDelegate] OpenTask notification posted")
        } else if let type = userInfo["type"] as? String, type == "test_reminder" {
            // Handle test notifications - create a test task for demonstration
            print("🧪 [NotificationDelegate] Test notification detected - showing test reminder")
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenTask"),
                object: nil,
                userInfo: ["taskId": "test", "isTestNotification": true]
            )
            print("✅ [NotificationDelegate] Test OpenTask notification posted")
        } else {
            print("⚠️ [NotificationDelegate] No taskId found in notification userInfo")
            print("⚠️ [NotificationDelegate] Cannot show reminder without taskId")
        }
    }

    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notification even when app is in foreground
        return [.banner, .sound, .badge]
    }
}

// MARK: - Notification Categories & Actions

extension NotificationManager {
    /// Register notification categories and actions
    func registerNotificationCategories() {
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE_ACTION",
            title: "Complete",
            options: .foreground
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: NSLocalizedString("timer.snooze_1hour", comment: "Snooze 1 hour"),
            options: []
        )

        let taskReminderCategory = UNNotificationCategory(
            identifier: "TASK_REMINDER",
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        center.setNotificationCategories([taskReminderCategory])
        print("✅ Registered notification categories")
    }
}
