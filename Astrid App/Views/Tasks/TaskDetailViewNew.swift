import SwiftUI

/// New TaskDetailView with inline editing (matching mobile web app)
struct TaskDetailViewNew: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean

    // Effective theme - Auto resolves to Light or Dark based on system setting
    private var effectiveTheme: ThemeMode {
        if themeMode == .auto {
            return colorScheme == .dark ? .dark : .light
        }
        return themeMode
    }

    @State private var task: Task
    let isReadOnly: Bool  // View-only mode for public lists
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @StateObject private var notificationPromptManager = NotificationPromptManager.shared

    // Editable state
    @State private var editedTitle: String
    @State private var editedDescription: String
    @State private var editedDueDate: Date?
    @State private var editedDueTime: Date?
    @State private var editedRepeating: Task.Repeating?
    @State private var editedRepeatingData: CustomRepeatingPattern?
    @State private var editedRepeatFrom: Task.RepeatFromMode?
    @State private var editedPriority: Task.Priority
    @State private var editedListIds: [String]
    @State private var editedAssigneeId: String?
    @State private var isCompleted: Bool
    @State private var isAllDay: Bool  // Track all-day state independently
    @State private var showTimer: Bool = false // New state for timer
    @FocusState private var isTitleFocused: Bool  // Focus state for title field

    init(task: Task, isReadOnly: Bool = false) {
        self._task = State(initialValue: task)
        self.isReadOnly = isReadOnly
        _editedTitle = State(initialValue: task.title)
        _editedDescription = State(initialValue: task.description)
        _editedDueDate = State(initialValue: task.dueDateTime)
        _editedDueTime = State(initialValue: task.isAllDay ? nil : task.dueDateTime)
        _editedRepeating = State(initialValue: task.repeating)
        _editedRepeatingData = State(initialValue: task.repeatingData)
        _editedRepeatFrom = State(initialValue: task.repeatFrom ?? .COMPLETION_DATE)
        _editedPriority = State(initialValue: task.priority)

        // 🔧 FIX: Compute listIds from lists array if not provided by API
        // This supports both old API (lists only) and new API (lists + listIds)
        let computedListIds: [String]
        if let listIds = task.listIds, !listIds.isEmpty {
            computedListIds = listIds
        } else if let lists = task.lists {
            computedListIds = lists.map { $0.id }
        } else {
            computedListIds = []
        }
        _editedListIds = State(initialValue: computedListIds)

        _editedAssigneeId = State(initialValue: task.assigneeId)
        _isCompleted = State(initialValue: task.completed)
        _isAllDay = State(initialValue: task.isAllDay)
    }

    // Check if task belongs to any PUBLIC list
    private var isPublicListTask: Bool {
        task.lists?.contains(where: { $0.privacy == .PUBLIC }) ?? false
    }

    var body: some View {
        mainContent
            // Hide "Task Details" title on iPad (shown in side panel with arrow indicator)
            .navigationTitle(UIDevice.current.userInterfaceIdiom == .pad ? "" : NSLocalizedString("tasks.task_details", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(UIDevice.current.userInterfaceIdiom == .pad)
            .task {
                await refreshTaskDetails()
            }
            .fullScreenCover(isPresented: $showTimer) {
                TaskTimerView(task: $task, onUpdate: { updatedTask in
                    self.task = updatedTask
                    // Sync local state with updated task
                    self.editedTitle = updatedTask.title
                    self.editedDescription = updatedTask.description
                    self.editedDueDate = updatedTask.dueDateTime
                    self.editedPriority = updatedTask.priority
                    self.isCompleted = updatedTask.completed
                })
            }
            .alert(NSLocalizedString("notifications.enable_push", comment: ""), isPresented: $notificationPromptManager.showPromptAlert) {
                Button(NSLocalizedString("notifications.not_now", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("notifications.enable", comment: "")) {
                    _Concurrency.Task {
                        _ = await notificationPromptManager.requestNotificationPermission()
                    }
                }
            } message: {
                Text(NSLocalizedString("notifications.enable_message", comment: ""))
            }
            .alert(NSLocalizedString("notifications.disabled", comment: ""), isPresented: $notificationPromptManager.showSettingsPrompt) {
                Button(NSLocalizedString("notifications.not_now", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("notifications.open_settings", comment: "")) {
                    notificationPromptManager.openSettings()
                }
            } message: {
                Text(NSLocalizedString("notifications.disabled_message", comment: ""))
            }
    }

    // MARK: - View Components

    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Theme.spacing24) {
                    // Anchor for scroll-to-top
                    Color.clear
                        .frame(height: 0)
                        .id("top")

                    // 1. Title and Completion Checkbox
                    HStack(alignment: .center, spacing: Theme.spacing12) {
                    // Checkbox using custom images matching task row (hide for read-only)
                    if !isReadOnly {
                        Button(action: toggleCompletion) {
                            checkboxImage
                        }
                        .buttonStyle(.plain)
                    }

                    // Title display
                    if isReadOnly {
                        Text(editedTitle)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.spacing12)
                            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    } else {
                        titleTextField
                    }
                }
                .padding(.horizontal, Theme.spacing16)
                .padding(.top, Theme.spacing16)
                .onChange(of: editedTitle) {
                    if !isReadOnly {
                        saveTitle()
                    }
                }

                Divider()
                    .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)

                // 2. Creator for public list tasks, Assignee for regular tasks (hidden for local users)
                if isPublicListTask || !AuthManager.shared.isLocalOnlyMode {
                    TwoColumnRow(label: isPublicListTask ? NSLocalizedString("tasks.created_by", comment: "") : NSLocalizedString("tasks.assignee", comment: "")) {
                        if isPublicListTask {
                            // Show creator with avatar for public list tasks (tappable to view profile)
                            if let creator = task.creator {
                                NavigationLink(destination: UserProfileView(userId: creator.id)) {
                                    HStack(spacing: Theme.spacing8) {
                                        // Creator avatar
                                        CachedAsyncImage(url: creator.image.flatMap { URL(string: $0) }) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(hex: "3b82f6") ?? Theme.accent)
                                                Text(creator.name?.prefix(1).uppercased() ?? creator.email?.prefix(1).uppercased() ?? "?")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .frame(width: 28, height: 28)
                                        .clipShape(Circle())

                                        Text(creator.displayName)
                                            .font(Theme.Typography.body())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } else if isReadOnly {
                            // Show assignee for read-only regular tasks
                            if let assignee = task.assignee {
                                Text(assignee.displayName)
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            } else {
                                Text(NSLocalizedString("assignee.unassigned", comment: ""))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                        } else {
                            // Show assignee picker for editable regular tasks
                            InlineAssigneePicker(
                                label: NSLocalizedString("tasks.assignee", comment: ""),
                                assigneeId: $editedAssigneeId,
                                taskListIds: editedListIds,
                                taskId: task.id,
                                availableLists: listService.lists,
                                onSave: saveAssignee,
                                showLabel: false
                            )
                        }
                    }
                }

                // 3. When (Due Date)
                if editedDueDate != nil || !isReadOnly {
                    TwoColumnRow(label: NSLocalizedString("tasks.due_date", comment: "")) {
                        if isReadOnly {
                            if let date = editedDueDate {
                                Text(formatDateReadOnly(date))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            }
                        } else {
                            InlineDatePicker(
                                label: NSLocalizedString("tasks.due_date", comment: ""),
                                date: $editedDueDate,
                                onSave: saveDueDate,
                                showLabel: false,
                                isAllDay: isAllDay
                            )
                        }
                    }
                }

                // 4. Time (conditional - only if date is set)
                if editedDueDate != nil {
                    if let time = editedDueTime, isReadOnly {
                        TwoColumnRow(label: "Time") {
                            Text(time, style: .time)
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        }
                    } else if !isReadOnly {
                        TwoColumnRow(label: "Time") {
                            InlineTimePicker(
                                label: "Time",
                                time: $editedDueTime,
                                onSave: saveDueTime,
                                showLabel: false
                            )
                        }
                    }
                }

                // 5. Repeat (conditional - only if date is set)
                if editedDueDate != nil {
                    if let repeating = editedRepeating, isReadOnly {
                        TwoColumnRow(label: "Repeat") {
                            Text(repeating.rawValue.capitalized)
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        }
                    } else if !isReadOnly {
                        TwoColumnRow(label: "Repeat") {
                            InlineRepeatPicker(
                                label: "Repeat",
                                repeatPattern: $editedRepeating,
                                repeatFrom: $editedRepeatFrom,
                                repeatingData: $editedRepeatingData,
                                onSave: saveRepeating,
                                onSaveCustom: saveCustomRepeating,
                                showLabel: false
                            )
                        }
                    }
                }

                // 6. Priority
                TwoColumnRow(label: "Priority") {
                    if isReadOnly {
                        HStack(spacing: Theme.spacing8) {
                            // Show priority icon/color
                            Circle()
                                .fill(priorityColor(editedPriority))
                                .frame(width: 12, height: 12)
                            Text(priorityText(editedPriority))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        }
                    } else {
                        PriorityButtonPicker(priority: $editedPriority) { newPriority in
                            _ = try await taskService.updateTask(taskId: task.id, priority: newPriority.rawValue, task: task)
                        }
                    }
                }

                // 7. Lists
                TwoColumnRow(label: "Lists") {
                    if isReadOnly {
                        if let lists = task.lists, !lists.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.spacing4) {
                                ForEach(lists) { list in
                                    HStack(spacing: Theme.spacing8) {
                                        ListImageView(list: list, size: 8)
                                        Text(list.name)
                                            .font(Theme.Typography.caption1())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    }
                                }
                            }
                        }
                    } else {
                        InlineListsPicker(
                            label: "Lists",
                            selectedListIds: $editedListIds,
                            availableLists: listService.lists,
                            onSave: saveLists,
                            showLabel: false
                        )
                    }
                }

                Divider()
                    .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)

                // 8. Description
                if isReadOnly {
                    // View-only: Only show description if it exists
                    if !editedDescription.isEmpty {
                        TwoColumnRow(label: "Description") {
                            Text(editedDescription)
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    InlineTextAreaEditor(
                        label: "Description",
                        text: $editedDescription,
                        placeholder: NSLocalizedString("task_edit.add_description", comment: "Add a description..."),
                        onSave: saveDescription
                    )
                    .padding(.horizontal, Theme.spacing16)
                    .onChange(of: editedDescription) {
                        if !isReadOnly {
                            saveDescription()
                        }
                    }
                }

                TaskAttachmentSectionView(task: task)

                // 9. Comments Section
                CommentSectionViewEnhanced(taskId: task.id)
                    .padding(.horizontal, Theme.spacing16)

                // 10. Timer Button
                VStack(spacing: Theme.spacing8) {
                    Button(action: { showTimer = true }) {
                        HStack {
                            Image(systemName: "timer")
                            Text("Timer")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing16)
                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
                        )
                    }

                    if let lastTimerValue = task.lastTimerValue {
                        Text(String(format: NSLocalizedString("task_edit.last_timer", comment: "Last timer value"), lastTimerValue))
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Theme.spacing16)
                .padding(.top, Theme.spacing8)

                // 10. Actions (hide for read-only)
                if !isReadOnly {
                    Divider()
                        .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)

                    TaskActionsView(
                        task: task,
                        currentListId: task.listIds?.first ?? task.lists?.first?.id
                    )
                    .padding(.horizontal, Theme.spacing16)
                }

                    Spacer().frame(height: Theme.spacing24)
                }
                .scrollToTopButton(proxy: proxy, topId: "top")
            }
            .coordinateSpace(name: "scroll")
            .refreshable {
                await refreshTaskDetails()
            }
            .background(
                ZStack {
                    getBackgroundColor()  // Ocean cyan base layer
                    if effectiveTheme == .ocean {
                        Color.white.opacity(0.8)  // Transparent white overlay for ocean theme
                    }
                }
            )
        }
    }

    // MARK: - Theme Helpers

    /// Get base background color (ocean cyan for ocean theme)
    private func getBackgroundColor() -> Color {
        switch effectiveTheme {
        case .ocean:
            return Theme.Ocean.bgPrimary  // Ocean cyan base
        case .dark:
            return Theme.Dark.bgPrimary
        case .light, .auto:
            return Theme.bgPrimary
        }
    }

    // MARK: - View Components (cont.)

    private var titleTextField: some View {
        TextField("Task title", text: $editedTitle, axis: .vertical)
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
            .textFieldStyle(.plain)
            .disabled(isReadOnly)
            .focused($isTitleFocused)
            .onChange(of: editedTitle) { _, newValue in
                // Detect return key press (newline) and dismiss keyboard
                if newValue.contains("\n") {
                    editedTitle = newValue.replacingOccurrences(of: "\n", with: "")
                    isTitleFocused = false
                }
            }
            .padding(Theme.spacing12)
            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }

    // MARK: - Helper Methods

    private func refreshTaskDetails() async {
        do {
            // Fetch fresh task data from the API with force refresh
            let freshTask = try await taskService.fetchTask(id: task.id, forceRefresh: true)

            // Update local state variables with fresh data
            await MainActor.run {
                self.task = freshTask
                editedTitle = freshTask.title
                editedDescription = freshTask.description
                editedDueDate = freshTask.dueDateTime
                editedDueTime = freshTask.isAllDay ? nil : freshTask.dueDateTime
                editedRepeating = freshTask.repeating
                editedRepeatingData = freshTask.repeatingData
                editedRepeatFrom = freshTask.repeatFrom ?? .COMPLETION_DATE
                editedPriority = freshTask.priority

                // Compute listIds from lists array if not provided by API
                let computedListIds: [String]
                if let listIds = freshTask.listIds, !listIds.isEmpty {
                    computedListIds = listIds
                } else if let lists = freshTask.lists {
                    computedListIds = lists.map { $0.id }
                } else {
                    computedListIds = []
                }
                editedListIds = computedListIds

                editedAssigneeId = freshTask.assigneeId
                isCompleted = freshTask.completed
                isAllDay = freshTask.isAllDay
            }

            // Reload comments using CommentService with force refresh
            _ = try? await CommentService.shared.fetchComments(taskId: task.id, useCache: false)
        } catch {
            // Silent failure - just fail gracefully if offline
            print("⚠️ [TaskDetailViewNew] Failed to refresh task details: \(error)")
        }
    }

    private var priorityColor: Color {
        switch editedPriority {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }

    /// Custom checkbox image matching task row design
    private var checkboxImage: some View {
        let priorityValue = editedPriority.rawValue
        let isRepeating = editedRepeating != nil && editedRepeating != .never
        let isChecked = isCompleted

        // Build image name: check_box[_repeat][_checked]_<priority>
        var imageName = "check_box"
        if isRepeating {
            imageName += "_repeat"
        }
        if isChecked {
            imageName += "_checked"
        }
        imageName += "_\(priorityValue)"

        return Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 34, height: 34)
    }

    private func toggleCompletion() {
        // Optimistic UI update
        isCompleted.toggle()

        // CRITICAL FIX for offline mode:
        // Create a copy of task with current edited values (especially repeating status).
        // When user changes a task from repeating to non-repeating offline, editedRepeating
        // is updated but task.repeating stays stale. TaskService needs the current state
        // to correctly handle completion (avoiding incorrect roll-forward for non-repeating tasks).
        var taskWithEdits = task
        taskWithEdits.repeating = editedRepeating
        taskWithEdits.repeatingData = editedRepeatingData
        taskWithEdits.repeatFrom = editedRepeatFrom

        // Sync to server in background
        _Concurrency.Task {
            do {
                let updatedTask = try await taskService.completeTask(id: task.id, completed: isCompleted, task: taskWithEdits)

                // For repeating tasks, server may roll forward (set completed back to false)
                // Update local state to match server response
                await MainActor.run {
                    isCompleted = updatedTask.completed

                    // Also update other fields that may have changed (due date for repeating tasks)
                    editedDueDate = updatedTask.dueDateTime
                    editedDueTime = updatedTask.isAllDay ? nil : updatedTask.dueDateTime

                    editedRepeating = updatedTask.repeating
                    editedRepeatingData = updatedTask.repeatingData

                    // Only set repeatFrom if task is still repeating
                    if updatedTask.repeating != nil && updatedTask.repeating != .never {
                        editedRepeatFrom = updatedTask.repeatFrom ?? .COMPLETION_DATE
                    } else {
                        editedRepeatFrom = nil
                        editedRepeatingData = nil
                    }
                }
            } catch {
                // On error, revert optimistic update
                await MainActor.run {
                    isCompleted.toggle()
                }
            }
        }
    }

    private func saveTitle() {
        guard editedTitle != task.title else { return }
        _Concurrency.Task {
            // CRITICAL: For tasks with custom repeating patterns, bypass TaskService
            // to prevent view recreation crashes during save
            if editedRepeating == .custom {
                let request = UpdateTaskRequest(title: editedTitle)
                if let updatedTask = try? await AstridAPIClient.shared.updateTask(id: task.id, updates: request) {
                    await MainActor.run { taskService.updateTaskInCache(updatedTask) }
                }
            } else {
                _ = try? await taskService.updateTask(taskId: task.id, title: editedTitle, task: task)
            }
        }
    }

    private func saveDescription() {
        guard editedDescription != task.description else { return }
        _Concurrency.Task {
            // CRITICAL: For tasks with custom repeating patterns, bypass TaskService
            // to prevent view recreation crashes during save
            if editedRepeating == .custom {
                let request = UpdateTaskRequest(description: editedDescription)
                if let updatedTask = try? await AstridAPIClient.shared.updateTask(id: task.id, updates: request) {
                    await MainActor.run { taskService.updateTaskInCache(updatedTask) }
                }
            } else {
                _ = try? await taskService.updateTask(taskId: task.id, description: editedDescription, task: task)
            }
        }
    }

    private func saveDueDate() {
        _Concurrency.Task {
            // If removing the due date, also clear repeating settings (matching web behavior)
            if editedDueDate == nil {
                editedRepeating = .never
                editedRepeatingData = nil
                editedDueTime = nil  // Also clear time when clearing date

                await MainActor.run {
                    isAllDay = true  // No date = all-day by default
                }

                // Use Date.distantPast as sentinel to signal "clear the date"
                _ = try? await taskService.updateTask(
                    taskId: task.id,
                    when: Date.distantPast,
                    whenTime: Date.distantPast,
                    repeating: "never",
                    repeatingData: nil,
                    task: task
                )
            } else {
                // If there's no time, it's an all-day task
                if editedDueTime == nil {
                    await MainActor.run {
                        isAllDay = true
                    }
                }

                // CRITICAL: For tasks with custom repeating patterns, bypass TaskService
                // to prevent view recreation crashes during save (same fix as saveCustomRepeating)
                if editedRepeating == .custom {
                    await saveDirectToAPI()
                } else {
                    // Set date only - preserve existing time if it exists
                    // Only pass whenTime if we need to change it (nil = don't update)
                    _ = try? await taskService.updateTask(
                        taskId: task.id,
                        when: editedDueDate,
                        whenTime: nil,  // nil = don't update time, preserve existing
                        task: task
                    )
                }

                // Check if we should prompt user to enable push notifications
                // This prompts 3 times initially, then once per month thereafter
                await notificationPromptManager.checkAndPromptAfterDateSet()
            }
        }
    }

    /// Direct API save for custom repeating tasks - bypasses TaskService optimistic update
    /// to prevent view recreation crashes during save
    private func saveDirectToAPI() async {
        guard let dueDate = editedDueDate else { return }

        // Format date for API
        var dueDateTimeString: String
        if isAllDay {
            // Normalize to UTC midnight for all-day tasks
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            let startOfDay = utcCalendar.startOfDay(for: dueDate)
            dueDateTimeString = ISO8601DateFormatter().string(from: startOfDay)
        } else if let time = editedDueTime {
            dueDateTimeString = ISO8601DateFormatter().string(from: time)
        } else {
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            let startOfDay = utcCalendar.startOfDay(for: dueDate)
            dueDateTimeString = ISO8601DateFormatter().string(from: startOfDay)
        }

        let request = UpdateTaskRequest(
            dueDateTime: dueDateTimeString,
            isAllDay: isAllDay
        )

        do {
            let updatedTask = try await AstridAPIClient.shared.updateTask(id: task.id, updates: request)
            await MainActor.run { taskService.updateTaskInCache(updatedTask) }
        } catch {
            print("⚠️ [TaskDetailViewNew] Direct API save failed: \(error)")
            // Silent failure - data will sync on next refresh
        }
    }

    private func savePriority() {
        guard editedPriority != task.priority else { return }
        _Concurrency.Task {
            // CRITICAL: For tasks with custom repeating patterns, bypass TaskService
            // to prevent view recreation crashes during save
            if editedRepeating == .custom {
                let request = UpdateTaskRequest(priority: editedPriority.rawValue)
                if let updatedTask = try? await AstridAPIClient.shared.updateTask(id: task.id, updates: request) {
                    await MainActor.run { taskService.updateTaskInCache(updatedTask) }
                }
            } else {
                _ = try? await taskService.updateTask(taskId: task.id, priority: editedPriority.rawValue, task: task)
            }
        }
    }

    private func saveDueTime() async {
        _Concurrency.Task {
            guard let date = editedDueDate else { return }

            if let time = editedDueTime {
                // Extract date components based on current all-day state
                let dateComponents: DateComponents

                if isAllDay {
                    // All-day → timed: Extract UTC components from UTC midnight date
                    var utcCalendar = Calendar(identifier: .gregorian)
                    utcCalendar.timeZone = TimeZone(identifier: "UTC")!
                    dateComponents = utcCalendar.dateComponents([.year, .month, .day], from: date)
                } else {
                    // Timed → timed: Extract LOCAL components to preserve date
                    let localCalendar = Calendar.current
                    dateComponents = localCalendar.dateComponents([.year, .month, .day], from: date)
                }

                // Extract LOCAL time components (hour, minute) - user's intended time
                let localCalendar = Calendar.current
                let timeComponents = localCalendar.dateComponents([.hour, .minute], from: time)

                // Combine: extracted date + local time = user's intended datetime
                var combined = DateComponents()
                combined.year = dateComponents.year
                combined.month = dateComponents.month
                combined.day = dateComponents.day
                combined.hour = timeComponents.hour
                combined.minute = timeComponents.minute
                combined.timeZone = localCalendar.timeZone  // User's timezone

                if let combinedDate = localCalendar.date(from: combined) {
                    // Update state immediately
                    await MainActor.run {
                        editedDueDate = combinedDate
                        isAllDay = false  // Now it's a timed task
                    }

                    // CRITICAL: For tasks with custom repeating patterns, bypass TaskService
                    // to prevent view recreation crashes during save
                    if editedRepeating == .custom {
                        await saveDirectToAPI()
                    } else {
                        // Send update to server
                        _ = try? await taskService.updateTask(
                            taskId: task.id,
                            when: combinedDate,
                            whenTime: combinedDate,
                            task: task
                        )
                    }
                }
            } else {
                // Time cleared - convert back to all-day task
                // CRITICAL: Update editedDueDate to UTC midnight
                // This ensures the date picker displays correctly when isAllDay becomes true
                // Use fresh Gregorian calendar to avoid device settings interference
                var utcCalendar = Calendar(identifier: .gregorian)
                utcCalendar.timeZone = TimeZone(identifier: "UTC")!

                // Extract current date components from the local date
                let localCalendar = Calendar.current
                let dateComponents = localCalendar.dateComponents([.year, .month, .day], from: date)

                // Create UTC midnight date with same calendar day
                if let utcMidnight = utcCalendar.date(from: dateComponents) {
                    await MainActor.run {
                        editedDueDate = utcMidnight
                        isAllDay = true  // Now it's an all-day task
                    }

                    // CRITICAL: For tasks with custom repeating patterns, bypass TaskService
                    if editedRepeating == .custom {
                        await saveDirectToAPI()
                    } else {
                        _ = try? await taskService.updateTask(
                            taskId: task.id,
                            when: utcMidnight,
                            whenTime: Date.distantPast,  // Clear time
                            task: task
                        )
                    }
                } else {
                    await MainActor.run {
                        isAllDay = true  // Now it's an all-day task
                    }

                    // CRITICAL: For tasks with custom repeating patterns, bypass TaskService
                    if editedRepeating == .custom {
                        await saveDirectToAPI()
                    } else {
                        _ = try? await taskService.updateTask(
                            taskId: task.id,
                            when: date,
                            whenTime: Date.distantPast,  // Clear time
                            task: task
                        )
                    }
                }
            }
        }
    }

    private func saveRepeating() async {
        _Concurrency.Task {
            let repeatingString = editedRepeating?.rawValue ?? "never"
            // Only send repeatingData if repeating is 'custom', otherwise clear it
            let dataToSend = (editedRepeating == .custom) ? editedRepeatingData : nil
            // Only send repeatFrom if repeating is not 'never'
            let repeatFromString = (editedRepeating != nil && editedRepeating != .never) ? editedRepeatFrom?.rawValue : nil
            _ = try? await taskService.updateTask(
                taskId: task.id,
                repeating: repeatingString,
                repeatingData: dataToSend,
                repeatFrom: repeatFromString,
                task: task
            )
        }
    }

    /// Direct save for custom repeating patterns - bypasses TaskService optimistic update
    /// to prevent view recreation crashes during save
    private func saveCustomRepeating(_ repeating: Task.Repeating, _ repeatFromMode: Task.RepeatFromMode, _ data: CustomRepeatingPattern?) async {
        // Update local state
        editedRepeating = repeating
        editedRepeatFrom = repeatFromMode
        editedRepeatingData = data

        // Call API directly - bypass TaskService to prevent view hierarchy crash
        let taskId = task.id
        do {
            let request = UpdateTaskRequest(
                repeating: repeating.rawValue,
                repeatingData: data,
                repeatFrom: repeatFromMode.rawValue
            )
            let updatedTask = try await AstridAPIClient.shared.updateTask(id: taskId, updates: request)

            // Update TaskService cache with the server response
            // This ensures the change persists when the task is reopened
            await MainActor.run {
                taskService.updateTaskInCache(updatedTask)
            }
        } catch {
            print("⚠️ [TaskDetailViewNew] Failed to save custom repeating: \(error)")
            // Silent failure - data will sync on next refresh
        }
    }

    private func saveLists() async {
        _Concurrency.Task {
            try? await taskService.updateTaskLists(taskId: task.id, listIds: editedListIds)
        }
    }

    private func saveAssignee(_ assigneeId: String?) async {
        _Concurrency.Task {
            // Convert nil to empty string to signal unassignment
            // nil = don't update, "" = unassign, "userId" = assign
            let assigneeIdForUpdate = assigneeId ?? ""
            _ = try? await taskService.updateTask(taskId: task.id, assigneeId: assigneeIdForUpdate, task: task)
        }
    }

    // MARK: - Read-Only Helpers

    private func formatDateReadOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        // For all-day tasks, use UTC timezone to show correct date
        if isAllDay {
            formatter.timeZone = TimeZone(identifier: "UTC")
        }

        return formatter.string(from: date)
    }

    private func priorityColor(_ priority: Task.Priority) -> Color {
        switch priority {
        case .none:
            return .gray
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private func priorityText(_ priority: Task.Priority) -> String {
        switch priority {
        case .none:
            return "None"
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

#Preview {
    NavigationStack {
        TaskDetailViewNew(task: Task(
            id: "1",
            title: "Sample Task",
            description: "This is a sample task",
            creatorId: "user1",
            isAllDay: false,
            repeating: .never,
            priority: .high,
            isPrivate: false,
            completed: false
        ))
    }
}
