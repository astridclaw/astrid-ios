# Astrid iOS Tests

Comprehensive test suite for the Astrid iOS app, similar to the web app's Vitest and Playwright infrastructure.

## Test Architecture

```
Astrid AppTests/
├── README.md                           # This file
├── TestConfig.swift                    # Test environment configuration
├── Tests/
│   ├── UnitTests/                      # Pure unit tests (no network)
│   │   ├── AuthenticationTests.swift   # Auth state, user identity, initials
│   │   ├── TaskModelTests.swift        # Task model & enums
│   │   ├── TaskCreationTests.swift     # Task creation, priorities, due dates
│   │   ├── UserModelTests.swift        # User model
│   │   ├── TaskListModelTests.swift    # TaskList model
│   │   ├── ListManagementTests.swift   # List creation, sharing, permissions
│   │   ├── SharedListTests.swift       # Shared list tasks, assignment
│   │   ├── CommentModelTests.swift     # Comments, replies, viewing others
│   │   ├── ReminderModelTests.swift    # Reminder types, times, offsets
│   │   ├── RecurringTaskModelTests.swift # Recurring patterns, workflows
│   │   ├── UserImageCacheTests.swift   # Profile photo caching & display
│   │   ├── RepeatingTaskCalculatorTests.swift  # Repeating logic
│   │   ├── PasskeyErrorTests.swift     # Passkey error handling
│   │   ├── EmailValidationTests.swift  # Email validation for auth
│   │   └── EmptyStateMessageTests.swift # Empty state message threshold logic
│   ├── IntegrationTests/
│   │   ├── CommentServiceIntegrationTests.swift  # Comment API tests
│   │   ├── ListMemberServiceIntegrationTests.swift  # List member API tests
│   │   └── ReminderSettingsIntegrationTests.swift   # Reminder sync tests
│   └── Mocks/
│       ├── TestHelpers.swift           # Factory methods for test data
│       └── MockAPIClient.swift         # Mock API client for testing
├── MCPClientListTests.swift            # List API integration tests
├── MCPClientTaskTests.swift            # Task API integration tests
├── ReminderSettingsSyncTests.swift     # Reminder sync tests
└── RepeatingTaskIntegrationTests.swift # Repeating task workflow tests

Astrid AppUITests/
├── Astrid_AppUITests.swift             # Basic UI tests
├── Astrid_AppUITestsLaunchTests.swift  # Launch performance
├── TaskUITests.swift                   # Task creation/completion UI
├── ListUITests.swift                   # List navigation UI
└── AuthUITests.swift                   # Authentication UI
```

## Test Types

### 1. Unit Tests (Fast, No Network)

Pure unit tests that run without network access. These test models, utilities, and pure functions.

**Run with:** `⌘U` in Xcode or `xcodebuild test -scheme "Astrid App" -only-testing:Astrid\ AppTests/TaskModelTests`

| Test File | Coverage |
|-----------|----------|
| `AuthenticationTests.swift` | User identity, initials, AI agents, pending users, profile images |
| `TaskModelTests.swift` | Task priority, repeating enums, task creation, extensions |
| `TaskCreationTests.swift` | Creating tasks with priorities, due dates, lists, assignments |
| `UserModelTests.swift` | User displayName, initials, AI agents, equality |
| `TaskListModelTests.swift` | List privacy, colors, members, invites |
| `ListManagementTests.swift` | List creation, sharing, privacy, member roles, permissions |
| `SharedListTests.swift` | Tasks in shared lists, assignment, visibility, collaboration |
| `CommentModelTests.swift` | Comments, replies, attachments, viewing from others |
| `ReminderModelTests.swift` | Reminder types (push/email/both), times, offsets |
| `RecurringTaskModelTests.swift` | Repeating patterns (daily/weekly/monthly/yearly), workflows |
| `UserImageCacheTests.swift` | Profile photo caching, cachedImageURL fallback, list/task member caching |
| `RepeatingTaskCalculatorTests.swift` | Daily/weekly/monthly/yearly calculations, end conditions |
| `PasskeyErrorTests.swift` | PasskeyError descriptions, existingUser error handling |
| `EmailValidationTests.swift` | Email validation for passkey registration flow |
| `EmptyStateMessageTests.swift` | Empty state message threshold logic (10+ tasks = "caught up") |

### 2. Integration Tests (Network Required)

Tests that interact with the Astrid API via MCP client. **Requires TEST_MCP_TOKEN**.

| Test File | Coverage |
|-----------|----------|
| `MCPClientTaskTests.swift` | Task CRUD operations |
| `MCPClientListTests.swift` | List CRUD operations |
| `ReminderSettingsSyncTests.swift` | Reminder sync, throttling, bidirectional sync |
| `RepeatingTaskIntegrationTests.swift` | Repeating task completion workflows |

### 3. UI Tests (XCUITest)

End-to-end UI tests that launch the app and interact with the interface.

| Test File | Coverage |
|-----------|----------|
| `TaskUITests.swift` | Quick add, completion, detail view, priority |
| `ListUITests.swift` | List navigation, selection, creation |
| `AuthUITests.swift` | Login screen, OAuth buttons, sign out |

---

## ⚠️ CRITICAL: Test User Configuration

**DO NOT run integration tests against production accounts!**

Integration tests create real data via the API. Use a dedicated test user.

### Setup Steps

#### 1. Create Test User Account

1. Go to https://astrid.cc
2. Sign up with email: `test+ios@astrid.cc` (or similar)
3. Verify email

#### 2. Generate MCP Token

1. Sign in as test user
2. Go to **Settings → MCP/API**
3. Generate a new MCP token
4. Copy the token (starts with `astrid_mcp_...`)

#### 3. Configure Xcode Test Scheme

1. In Xcode, select **Product → Scheme → Edit Scheme**
2. Select **Test** in left sidebar
3. Click **Arguments** tab
4. Under **Environment Variables**, add:
   - **Name:** `TEST_MCP_TOKEN`
   - **Value:** `<paste-your-test-token-here>`
5. Click **Close**

#### 4. Run Tests

Now when you run tests (⌘U), they will:
- ✅ Use the dedicated test user
- ✅ Skip gracefully if `TEST_MCP_TOKEN` not set
- ✅ Show clear error message if misconfigured

---

## Running Tests

### All Tests
```bash
# In Xcode
⌘U

# Command line
xcodebuild test -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 15"
```

### Unit Tests Only (Fast)
```bash
xcodebuild test -scheme "Astrid App" \
  -only-testing:Astrid\ AppTests/TaskModelTests \
  -only-testing:Astrid\ AppTests/UserModelTests \
  -only-testing:Astrid\ AppTests/TaskListModelTests \
  -only-testing:Astrid\ AppTests/RepeatingTaskCalculatorTests \
  -only-testing:Astrid\ AppTests/EmptyStateMessageTests \
  -destination "platform=iOS Simulator,name=iPhone 15"
```

### Integration Tests Only
```bash
xcodebuild test -scheme "Astrid App" \
  -only-testing:Astrid\ AppTests/MCPClientTaskTests \
  -only-testing:Astrid\ AppTests/MCPClientListTests \
  -only-testing:Astrid\ AppTests/ReminderSettingsSyncTests \
  -only-testing:Astrid\ AppTests/RepeatingTaskIntegrationTests \
  -destination "platform=iOS Simulator,name=iPhone 15"
```

### UI Tests Only
```bash
xcodebuild test -scheme "Astrid App" \
  -only-testing:Astrid\ AppUITests \
  -destination "platform=iOS Simulator,name=iPhone 15"
```

---

## Test Patterns

### Unit Test Pattern (AAA)
```swift
func testPriorityDisplayNames() {
    // Arrange - (implicit via enum definition)

    // Act
    let highName = Task.Priority.high.displayName

    // Assert
    XCTAssertEqual(highName, "High")
}
```

### Integration Test Pattern
```swift
func testCreateTaskWithTitle() async throws {
    // Given
    let testList = try await createTestList()
    let taskTitle = "Test Task \(UUID().uuidString)"

    // When
    let response = try await mcpClient.createTask(
        listIds: [testList.id],
        title: taskTitle,
        ...
    )

    // Then
    XCTAssertEqual(response.task.title, taskTitle)

    // Cleanup
    _ = try await mcpClient.deleteTask(taskId: response.task.id)
}
```

### UI Test Pattern
```swift
@MainActor
func testCreateTask() throws {
    app.launch()

    // Skip if not authenticated
    if app.buttons["Sign in with Apple"].exists {
        throw XCTSkip("User not authenticated")
    }

    // Find and interact with UI
    let taskInput = app.textFields["Add a task..."]
    taskInput.tap()
    taskInput.typeText("New Task")
    app.keyboards.buttons["Return"].tap()

    // Verify
    XCTAssertTrue(app.staticTexts["New Task"].exists)
}
```

---

## Test Helpers

The `TestHelpers.swift` file provides factory methods for creating test data:

```swift
// Create test user
let user = TestHelpers.createTestUser(id: "user-1", name: "Alice")

// Create test task
let task = TestHelpers.createTestTask(
    title: "My Task",
    priority: .high,
    dueDateTime: Date()
)

// Create repeating task
let repeatingTask = TestHelpers.createRepeatingTask(
    repeating: .weekly,
    repeatFrom: .DUE_DATE
)

// Create test list
let list = TestHelpers.createTestList(
    name: "Work",
    privacy: .SHARED
)

// Create custom repeating pattern
let pattern = TestHelpers.createWeeklyPattern(
    weekdays: ["monday", "wednesday", "friday"]
)

// Create dates
let tomorrow = TestHelpers.createRelativeDate(daysFromNow: 1)
let specificDate = TestHelpers.createDate(year: 2024, month: 6, day: 15)
```

---

## Coverage by Feature

### Authentication Features
- ✅ User identity (name → email → "Unknown User" fallback)
- ✅ Initials generation (first letters of name/email)
- ✅ AI agent identification
- ✅ Pending user status
- ✅ Profile image and cached image URL
- ✅ Default due time settings

### Task Features
- ✅ Priority levels (none, low, medium, high)
- ✅ Task creation in My Tasks
- ✅ Quick priority setting
- ✅ Due dates and times (all-day vs timed)
- ✅ Repeating patterns (daily, weekly, monthly, yearly, custom)
- ✅ Repeat from mode (due date vs completion date)
- ✅ End conditions (never, after X occurrences, until date)
- ✅ Task creation with all fields
- ✅ Task completion and uncomplete
- ✅ Due date changes
- ✅ Creator/assignee tracking
- ✅ Attachments and comments

### List Features
- ✅ List creation (private, shared, public)
- ✅ Default colors
- ✅ List sharing and member invites
- ✅ Member roles (owner, admin, member)
- ✅ Default task settings (assignee, priority, repeating)
- ✅ MCP/AI settings
- ✅ Favorite lists
- ✅ Virtual lists

### Shared List Features
- ✅ Create tasks in shared lists
- ✅ Assign tasks to members
- ✅ Reassign tasks
- ✅ Private tasks in shared lists
- ✅ Member visibility checks
- ✅ Default assignee settings

### Comment Features
- ✅ Text and markdown comments
- ✅ Attachment comments
- ✅ Comment replies (threading)
- ✅ Viewing comments from other users
- ✅ AI agent comments
- ✅ Comment timestamps and ordering

### Reminder Features
- ✅ Reminder types (push, email, both)
- ✅ Reminder time offsets (5min to 1 day before)
- ✅ Reminder at due time
- ✅ Reminder sent status
- ✅ Reminders on all-day tasks
- ✅ Reminders with assignments

### Recurring Task Features
- ✅ Simple patterns (daily, weekly, monthly, yearly)
- ✅ Custom daily (every N days)
- ✅ Custom weekly with specific weekdays
- ✅ Custom monthly (same date or same weekday)
- ✅ Custom yearly
- ✅ End after X occurrences
- ✅ End until date
- ✅ Repeat from due date vs completion date
- ✅ Occurrence count tracking
- ✅ Date helper extensions

---

## Cleaning Up Test Data

If test data was accidentally created on a production account:

```bash
# From www/ directory
npx tsx scripts/cleanup-test-lists.ts <email>

# Example
npx tsx scripts/cleanup-test-lists.ts wonk1@kuoparis.com
```

This deletes lists matching test patterns:
- Names starting with: "Test List", "Repeat Test List", "Batch Task"
- Descriptions containing: "Test list for", "test description"

---

## CI/CD Integration

For CI/CD pipelines, set the `TEST_MCP_TOKEN` as an environment variable:

```yaml
# GitHub Actions example
env:
  TEST_MCP_TOKEN: ${{ secrets.IOS_TEST_MCP_TOKEN }}
```

```bash
# Run tests in CI
xcodebuild test \
  -scheme "Astrid App" \
  -destination "platform=iOS Simulator,name=iPhone 15" \
  -resultBundlePath TestResults.xcresult
```

---

## Future Improvements

- [ ] Snapshot tests for UI components
- [ ] Performance tests for large task lists
- [ ] Accessibility tests
- [ ] Mock API client for faster unit tests
- [ ] Network simulation (offline, slow, errors)
- [ ] Memory leak detection
- [ ] Code coverage reporting

---

## Related Documentation

- [API Contract](../docs/API_CONTRACT.md) - Backend API specification
- [Local-First Pattern](../docs/LOCAL_FIRST_PATTERN.md) - Offline architecture
- [Web App](https://github.com/Graceful-Tools/astrid-web) - Web app repository
