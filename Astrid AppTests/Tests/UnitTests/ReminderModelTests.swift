import XCTest
@testable import Astrid_App

/// Unit tests for reminder functionality
/// Tests reminder types, reminder times, and task reminder settings
final class ReminderModelTests: XCTestCase {

    // MARK: - Reminder Type Tests

    func testReminderTypePush() {
        // Given: A task with push reminder
        let task = TestHelpers.createTestTask(reminderType: .push)

        // Then: Reminder type should be push
        XCTAssertEqual(task.reminderType, .push)
        XCTAssertEqual(task.reminderType?.rawValue, "push")
    }

    func testReminderTypeEmail() {
        // Given: A task with email reminder
        let task = TestHelpers.createTestTask(reminderType: .email)

        // Then: Reminder type should be email
        XCTAssertEqual(task.reminderType, .email)
        XCTAssertEqual(task.reminderType?.rawValue, "email")
    }

    func testReminderTypeBoth() {
        // Given: A task with both reminder types
        let task = TestHelpers.createTestTask(reminderType: .both)

        // Then: Reminder type should be both
        XCTAssertEqual(task.reminderType, .both)
        XCTAssertEqual(task.reminderType?.rawValue, "both")
    }

    func testTaskWithoutReminder() {
        // Given: A task without reminder
        let task = TestHelpers.createTestTask(reminderTime: nil, reminderType: nil)

        // Then: Reminder should be nil
        XCTAssertNil(task.reminderType)
        XCTAssertNil(task.reminderTime)
    }

    // MARK: - Reminder Time Tests

    func testReminderTimeSet() {
        // Given: A task with reminder time
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 14, minute: 0)
        let reminderTime = dueDate.addingTimeInterval(-3600)  // 1 hour before

        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            isAllDay: false,
            reminderTime: reminderTime,
            reminderType: .push
        )

        // Then: Reminder time should be set
        XCTAssertNotNil(task.reminderTime)
        XCTAssertEqual(task.reminderTime, reminderTime)
    }

    func testReminderTimeBeforeDueDate() {
        // Given: A task with due date and reminder
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 10, minute: 0)
        let reminderTime = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 9, minute: 0)

        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            reminderTime: reminderTime
        )

        // Then: Reminder should be before due date
        XCTAssertTrue(task.reminderTime! < task.dueDateTime!)
    }

    func testReminderSentStatus() {
        // Given: A task with reminder that hasn't been sent
        let task1 = TestHelpers.createTestTask(
            reminderTime: Date().addingTimeInterval(3600),
            reminderSent: false,
            reminderType: .push
        )

        // Then: Reminder should not be sent
        XCTAssertEqual(task1.reminderSent, false)

        // Given: A task with reminder that has been sent
        let task2 = Task(
            id: "sent-reminder-task",
            title: "Task with sent reminder",
            description: "",
            assigneeId: nil,
            assignee: nil,
            creatorId: nil,
            creator: nil,
            dueDateTime: Date().addingTimeInterval(-3600),
            isAllDay: false,
            reminderTime: Date().addingTimeInterval(-7200),
            reminderSent: true,
            reminderType: .push,
            repeating: nil,
            repeatingData: nil,
            repeatFrom: nil,
            occurrenceCount: nil,
            priority: .none,
            lists: nil,
            listIds: nil,
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: nil,
            updatedAt: nil,
            originalTaskId: nil,
            sourceListId: nil
        )

        // Then: Reminder should be sent
        XCTAssertEqual(task2.reminderSent, true)
    }

    // MARK: - Reminder Offset Tests

    func testReminderAtTime() {
        // Given: A reminder at the task due time
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 14, minute: 0)
        let reminderTime = dueDate  // Same as due time

        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            reminderTime: reminderTime
        )

        // Then: Reminder time should equal due time
        XCTAssertEqual(task.reminderTime, task.dueDateTime)
    }

    func testReminder5MinutesBefore() {
        // Given: A reminder 5 minutes before
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 14, minute: 0)
        let reminderTime = dueDate.addingTimeInterval(-5 * 60)  // 5 minutes before

        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            reminderTime: reminderTime
        )

        // Then: Offset should be 5 minutes
        let offset = task.dueDateTime!.timeIntervalSince(task.reminderTime!)
        XCTAssertEqual(offset, 5 * 60, accuracy: 1)
    }

    func testReminder15MinutesBefore() {
        // Given: A reminder 15 minutes before
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 14, minute: 0)
        let reminderTime = dueDate.addingTimeInterval(-15 * 60)

        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            reminderTime: reminderTime
        )

        // Then: Offset should be 15 minutes
        let offset = task.dueDateTime!.timeIntervalSince(task.reminderTime!)
        XCTAssertEqual(offset, 15 * 60, accuracy: 1)
    }

    func testReminder30MinutesBefore() {
        // Given: A reminder 30 minutes before
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 14, minute: 0)
        let reminderTime = dueDate.addingTimeInterval(-30 * 60)

        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            reminderTime: reminderTime
        )

        // Then: Offset should be 30 minutes
        let offset = task.dueDateTime!.timeIntervalSince(task.reminderTime!)
        XCTAssertEqual(offset, 30 * 60, accuracy: 1)
    }

    func testReminder1HourBefore() {
        // Given: A reminder 1 hour before
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 14, minute: 0)
        let reminderTime = dueDate.addingTimeInterval(-60 * 60)

        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            reminderTime: reminderTime
        )

        // Then: Offset should be 1 hour
        let offset = task.dueDateTime!.timeIntervalSince(task.reminderTime!)
        XCTAssertEqual(offset, 60 * 60, accuracy: 1)
    }

    func testReminder1DayBefore() {
        // Given: A reminder 1 day before
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 14, minute: 0)
        let reminderTime = dueDate.addingTimeInterval(-24 * 60 * 60)

        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            reminderTime: reminderTime
        )

        // Then: Offset should be 1 day
        let offset = task.dueDateTime!.timeIntervalSince(task.reminderTime!)
        XCTAssertEqual(offset, 24 * 60 * 60, accuracy: 1)
    }

    // MARK: - All Day Task Reminder Tests

    func testAllDayTaskWithReminder() {
        // Given: An all-day task with reminder
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 9, minute: 0)
        let reminderTime = TestHelpers.createDate(year: 2024, month: 6, day: 14, hour: 9, minute: 0)  // Day before

        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            isAllDay: true,
            reminderTime: reminderTime,
            reminderType: .push
        )

        // Then: Reminder should be set for all-day task
        XCTAssertTrue(task.isAllDay)
        XCTAssertNotNil(task.reminderTime)
    }

    // MARK: - Reminder with Priority Tests

    func testHighPriorityTaskWithReminder() {
        // Given: A high-priority task with reminder
        let dueDate = TestHelpers.createRelativeDate(daysFromNow: 1)
        let reminderTime = dueDate.addingTimeInterval(-3600)

        let task = TestHelpers.createTestTask(
            title: "Urgent meeting",
            priority: .high,
            dueDateTime: dueDate,
            reminderTime: reminderTime,
            reminderType: .both
        )

        // Then: Task should have high priority and reminder
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.reminderType, .both)
        XCTAssertNotNil(task.reminderTime)
    }

    // MARK: - Complete Reminder Workflow Tests

    func testCreateTaskWithReminderWorkflow() {
        // Simulates: User creates a task with due date and reminder

        // Step 1: Set up due date (tomorrow at 2 PM)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = 14
        components.minute = 0
        let dueDate = calendar.date(from: components)!

        // Step 2: Set reminder 1 hour before
        let reminderTime = dueDate.addingTimeInterval(-3600)

        // Step 3: Create task
        let task = TestHelpers.createTestTask(
            id: "reminder-workflow-task",
            title: "Project deadline",
            priority: .high,
            dueDateTime: dueDate,
            isAllDay: false,
            reminderTime: reminderTime,
            reminderSent: false,
            reminderType: .push
        )

        // Verify workflow
        XCTAssertEqual(task.title, "Project deadline")
        XCTAssertEqual(task.priority, .high)
        XCTAssertFalse(task.isAllDay)
        XCTAssertNotNil(task.dueDateTime)
        XCTAssertNotNil(task.reminderTime)
        XCTAssertEqual(task.reminderType, .push)
        XCTAssertEqual(task.reminderSent, false)

        // Verify reminder is before due date
        XCTAssertTrue(task.reminderTime! < task.dueDateTime!)

        // Verify offset is 1 hour
        let offset = task.dueDateTime!.timeIntervalSince(task.reminderTime!)
        XCTAssertEqual(offset, 3600, accuracy: 1)
    }

    // MARK: - Reminder Edge Cases

    func testReminderWithNoDueDate() {
        // Given: A task with reminder but no due date
        let reminderTime = Date().addingTimeInterval(3600)

        let task = TestHelpers.createTestTask(
            dueDateTime: nil,
            reminderTime: reminderTime,
            reminderType: .push
        )

        // Then: Reminder should still be set
        XCTAssertNil(task.dueDateTime)
        XCTAssertNotNil(task.reminderTime)
    }

    func testDueDateWithNoReminder() {
        // Given: A task with due date but no reminder
        let dueDate = TestHelpers.createRelativeDate(daysFromNow: 1)

        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            reminderTime: nil,
            reminderType: nil
        )

        // Then: Reminder should be nil
        XCTAssertNotNil(task.dueDateTime)
        XCTAssertNil(task.reminderTime)
        XCTAssertNil(task.reminderType)
    }

    func testMultipleTasksWithDifferentReminderTypes() {
        // Given: Tasks with different reminder types
        let dueDate = TestHelpers.createRelativeDate(daysFromNow: 1)
        let reminderTime = dueDate.addingTimeInterval(-3600)

        let pushTask = TestHelpers.createTestTask(
            id: "push-task",
            title: "Push Only",
            dueDateTime: dueDate,
            reminderTime: reminderTime,
            reminderType: .push
        )

        let emailTask = TestHelpers.createTestTask(
            id: "email-task",
            title: "Email Only",
            dueDateTime: dueDate,
            reminderTime: reminderTime,
            reminderType: .email
        )

        let bothTask = TestHelpers.createTestTask(
            id: "both-task",
            title: "Both Types",
            dueDateTime: dueDate,
            reminderTime: reminderTime,
            reminderType: .both
        )

        // Then: Each should have correct reminder type
        XCTAssertEqual(pushTask.reminderType, .push)
        XCTAssertEqual(emailTask.reminderType, .email)
        XCTAssertEqual(bothTask.reminderType, .both)
    }

    // MARK: - Reminder in Shared List Tests

    func testReminderOnAssignedTask() {
        // Given: An assigned task with reminder
        let assignee = TestHelpers.createTestUser(id: "assignee-123", name: "Assignee")
        let dueDate = TestHelpers.createRelativeDate(daysFromNow: 2)
        let reminderTime = dueDate.addingTimeInterval(-3600)

        let task = TestHelpers.createTestTask(
            title: "Assigned task with reminder",
            dueDateTime: dueDate,
            assigneeId: assignee.id,
            assignee: assignee,
            reminderTime: reminderTime,
            reminderType: .push
        )

        // Then: Task should have both assignee and reminder
        XCTAssertEqual(task.assigneeId, "assignee-123")
        XCTAssertNotNil(task.reminderTime)
        XCTAssertEqual(task.reminderType, .push)
    }

    // MARK: - Past Reminder Tests

    func testPastReminderNotSent() {
        // Given: A task with past reminder that wasn't sent
        let pastDueDate = Date().addingTimeInterval(-7200)  // 2 hours ago
        let pastReminderTime = pastDueDate.addingTimeInterval(-3600)  // 3 hours ago

        let task = Task(
            id: "past-task",
            title: "Past Task",
            description: "",
            assigneeId: nil,
            assignee: nil,
            creatorId: nil,
            creator: nil,
            dueDateTime: pastDueDate,
            isAllDay: false,
            reminderTime: pastReminderTime,
            reminderSent: false,
            reminderType: .push,
            repeating: nil,
            repeatingData: nil,
            repeatFrom: nil,
            occurrenceCount: nil,
            priority: .none,
            lists: nil,
            listIds: nil,
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: nil,
            updatedAt: nil,
            originalTaskId: nil,
            sourceListId: nil
        )

        // Then: Reminder time should be in the past
        XCTAssertTrue(task.reminderTime! < Date())
        XCTAssertEqual(task.reminderSent, false)
    }

    func testPastReminderSent() {
        // Given: A task with past reminder that was sent
        let pastDueDate = Date().addingTimeInterval(-7200)
        let pastReminderTime = pastDueDate.addingTimeInterval(-3600)

        let task = Task(
            id: "sent-past-task",
            title: "Sent Past Task",
            description: "",
            assigneeId: nil,
            assignee: nil,
            creatorId: nil,
            creator: nil,
            dueDateTime: pastDueDate,
            isAllDay: false,
            reminderTime: pastReminderTime,
            reminderSent: true,
            reminderType: .push,
            repeating: nil,
            repeatingData: nil,
            repeatFrom: nil,
            occurrenceCount: nil,
            priority: .none,
            lists: nil,
            listIds: nil,
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: nil,
            updatedAt: nil,
            originalTaskId: nil,
            sourceListId: nil
        )

        // Then: Reminder should be marked as sent
        XCTAssertEqual(task.reminderSent, true)
    }
}
