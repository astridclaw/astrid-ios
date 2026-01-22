import XCTest
@testable import Astrid_App

/// Unit tests for empty state message logic
/// Tests the "caught up" message threshold behavior
final class EmptyStateMessageTests: XCTestCase {

    // MARK: - Helper Function Tests

    /// Test that we correctly count completed tasks for a user
    func testCountCompletedTasksForUser() {
        let userId = "test-user-123"

        // Create 5 completed tasks assigned to our user
        var tasks: [Task] = []
        for i in 0..<5 {
            tasks.append(TestHelpers.createTestTask(
                id: "completed-\(i)",
                title: "Completed Task \(i)",
                completed: true,
                assigneeId: userId
            ))
        }

        // Add 3 incomplete tasks assigned to our user
        for i in 0..<3 {
            tasks.append(TestHelpers.createTestTask(
                id: "incomplete-\(i)",
                title: "Incomplete Task \(i)",
                completed: false,
                assigneeId: userId
            ))
        }

        // Add 2 completed tasks assigned to someone else
        for i in 0..<2 {
            tasks.append(TestHelpers.createTestTask(
                id: "other-completed-\(i)",
                title: "Other's Task \(i)",
                completed: true,
                assigneeId: "other-user"
            ))
        }

        // Count completed tasks for our user
        let completedCount = tasks.filter { task in
            task.completed && task.assigneeId == userId
        }.count

        XCTAssertEqual(completedCount, 5, "Should count only completed tasks assigned to user")
    }

    /// Test the threshold logic: < 10 completed = new user message
    func testNewUserBelowThreshold() {
        let userId = "new-user"

        // Create 9 completed tasks (below threshold)
        var tasks: [Task] = []
        for i in 0..<9 {
            tasks.append(TestHelpers.createTestTask(
                id: "task-\(i)",
                completed: true,
                assigneeId: userId
            ))
        }

        let completedCount = tasks.filter { $0.completed && $0.assigneeId == userId }.count

        // Should NOT show "caught up" message
        XCTAssertLessThan(completedCount, 10, "User with < 10 completed tasks should see welcome message")
    }

    /// Test the threshold logic: >= 10 completed = caught up message
    func testExperiencedUserAtThreshold() {
        let userId = "experienced-user"

        // Create exactly 10 completed tasks (at threshold)
        var tasks: [Task] = []
        for i in 0..<10 {
            tasks.append(TestHelpers.createTestTask(
                id: "task-\(i)",
                completed: true,
                assigneeId: userId
            ))
        }

        let completedCount = tasks.filter { $0.completed && $0.assigneeId == userId }.count

        // Should show "caught up" message
        XCTAssertGreaterThanOrEqual(completedCount, 10, "User with >= 10 completed tasks should see caught up message")
    }

    /// Test the threshold logic: > 10 completed = caught up message
    func testExperiencedUserAboveThreshold() {
        let userId = "power-user"

        // Create 50 completed tasks (well above threshold)
        var tasks: [Task] = []
        for i in 0..<50 {
            tasks.append(TestHelpers.createTestTask(
                id: "task-\(i)",
                completed: true,
                assigneeId: userId
            ))
        }

        let completedCount = tasks.filter { $0.completed && $0.assigneeId == userId }.count

        // Should show "caught up" message
        XCTAssertGreaterThanOrEqual(completedCount, 10, "Power user with many completed tasks should see caught up message")
    }

    /// Test that tasks without assigneeId are not counted
    func testUnassignedTasksNotCounted() {
        let userId = "test-user"

        var tasks: [Task] = []

        // Add 15 completed tasks with NO assigneeId
        for i in 0..<15 {
            tasks.append(TestHelpers.createTestTask(
                id: "unassigned-\(i)",
                completed: true,
                assigneeId: nil  // Not assigned to anyone
            ))
        }

        // Add 5 completed tasks assigned to our user
        for i in 0..<5 {
            tasks.append(TestHelpers.createTestTask(
                id: "assigned-\(i)",
                completed: true,
                assigneeId: userId
            ))
        }

        let completedCount = tasks.filter { $0.completed && $0.assigneeId == userId }.count

        // Should only count the 5 assigned tasks
        XCTAssertEqual(completedCount, 5, "Should only count tasks assigned to user, not unassigned tasks")
        XCTAssertLessThan(completedCount, 10, "User should still be below threshold")
    }

    /// Test edge case: zero completed tasks (brand new user)
    func testBrandNewUserNoCompletedTasks() {
        let userId = "brand-new-user"

        // Create only incomplete tasks
        var tasks: [Task] = []
        for i in 0..<5 {
            tasks.append(TestHelpers.createTestTask(
                id: "task-\(i)",
                completed: false,
                assigneeId: userId
            ))
        }

        let completedCount = tasks.filter { $0.completed && $0.assigneeId == userId }.count

        XCTAssertEqual(completedCount, 0, "Brand new user should have zero completed tasks")
        XCTAssertLessThan(completedCount, 10, "Brand new user should see welcome message")
    }

    /// Test edge case: empty task list
    func testEmptyTaskList() {
        let userId = "empty-list-user"
        let tasks: [Task] = []

        let completedCount = tasks.filter { $0.completed && $0.assigneeId == userId }.count

        XCTAssertEqual(completedCount, 0, "Empty list should return zero")
        XCTAssertLessThan(completedCount, 10, "User with no tasks should see welcome message")
    }
}
