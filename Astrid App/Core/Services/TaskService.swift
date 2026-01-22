import Foundation
import Combine
import CoreData
import UIKit

/// Task service using API v1 with offline support via CoreData
/// Handles task operations and syncing across all user's lists
@MainActor
class TaskService: ObservableObject {
    static let shared = TaskService()

    @Published var tasks: [Task] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingOperationsCount: Int = 0
    @Published var failedOperationsCount: Int = 0
    @Published var isSyncingPendingOperations = false
    @Published var hasCompletedInitialLoad = false  // Track if initial data load is done

    private let apiClient = AstridAPIClient.shared
    private let notificationManager = NotificationManager.shared
    private let badgeManager = BadgeManager.shared
    private let coreDataManager = CoreDataManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var cachedTasks: [String: Task] = [:]
    private var syncTimer: Timer?
    private var networkObserver: NSObjectProtocol?

    /// Mapping of temp list IDs to their real server IDs (populated when lists sync)
    private var tempListIdMapping: [String: String] = [:]

    private init() {
        setupNetworkObserver()
        startBackgroundSync()
        // REMOVED: setupAppLifecycleObserver() - Saving all tasks to Core Data freezes the app

        // Load cached tasks synchronously to ensure data is available before any UI renders
        // This is CRITICAL for offline mode - tasks must be in memory before network calls fail
        loadCachedTasks()
    }

    // MARK: - Initialization

    /// Load cached tasks from CoreData on startup (synchronous, blocking)
    /// CRITICAL: This must be synchronous to ensure tasks are loaded before UI renders
    /// Without this, opening the app offline shows no tasks even though they're cached
    private func loadCachedTasks() {
        do {
            // Load from viewContext synchronously on main thread
            // This is safe because init() already runs on MainActor and reads are fast
            let fetchRequest = CDTask.fetchRequest()
            let cdTasks = try coreDataManager.viewContext.fetch(fetchRequest)

            // Convert to domain models
            self.tasks = cdTasks.map { $0.toDomainModel() }
            for task in self.tasks {
                cachedTasks[task.id] = task
            }
            updatePendingOperationsCount()
            print("✅ [TaskService] Loaded \(tasks.count) tasks from cache synchronously (\(pendingOperationsCount) pending)")
            // Mark as loaded IMMEDIATELY so UI shows cached data right away
            // This is critical for offline mode - user sees data even before network sync
            self.hasCompletedInitialLoad = true
        } catch {
            print("❌ [TaskService] Failed to load cached tasks: \(error)")
            self.hasCompletedInitialLoad = true  // Mark as loaded even on error to not block UI
        }
    }

    /// Setup network observer to sync when connection is restored
    private func setupNetworkObserver() {
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                print("🔄 [TaskService] Network restored - syncing pending operations")
                try? await self?.syncPendingOperations()
            }
        }
    }

    /// DISABLED: Setup app lifecycle observer to save to Core Data when app goes to background
    /// 🚨 ISSUE: Saving all tasks to Core Data (even in background) freezes the app
    /// Core Data NSManagedObject creation is too expensive for hundreds of tasks
    /// Tasks now remain in memory only, with Core Data used ONLY for pending operations
    private func setupAppLifecycleObserver() {
        // DISABLED - This method is not called from init() to prevent app freezing
        // Keeping method for reference but functionality is disabled

        // OLD CODE (caused freezing):
        // NotificationCenter.default.addObserver(
        //     forName: UIApplication.didEnterBackgroundNotification,
        //     object: nil,
        //     queue: .main
        // ) { [weak self] _ in
        //     guard let self = self else { return }
        //     print("💾 [TaskService] App entering background - saving to Core Data...")
        //
        //     _Concurrency.Task.detached { [weak self] in
        //         guard let self = self else { return }
        //         do {
        //             let tasksToSave = await MainActor.run { Array(self.tasks) }
        //             try await self.saveTasksToCoreData(tasksToSave)
        //             print("✅ [TaskService] Saved \(tasksToSave.count) tasks to Core Data")
        //         } catch {
        //             print("⚠️ [TaskService] Failed to save tasks on background: \(error)")
        //         }
        //     }
        // }
    }

    /// Start background sync timer (every 60 seconds)
    private func startBackgroundSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                guard let self = self else { return }
                // Only sync if we have pending operations and network is available
                if self.pendingOperationsCount > 0 && self.networkMonitor.isConnected {
                    try? await self.syncPendingOperations()
                }
            }
        }
    }

    deinit {
        syncTimer?.invalidate()
        if let observer = networkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Initial Sync

    /// Fetch all tasks from all accessible lists
    func fetchAllTasks() async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Fetch ALL tasks assigned to the user (including tasks without lists!)
            print("📡 [TaskService] Fetching all user tasks...")
            let uniqueTasks = try await apiClient.getAllTasks()
            print("✅ [TaskService] Fetched \(uniqueTasks.count) tasks from server")

            // CRITICAL: Merge with existing in-memory tasks instead of replacing
            // Keep any tasks with temp_ IDs (not synced yet) or valid tasks not in server response
            let serverTaskIds = Set(uniqueTasks.map { $0.id })
            let pendingTasks = self.tasks.filter { task in
                // Only keep temp tasks (not synced yet)
                // Don't keep corrupt cached tasks (empty title, no ID, etc.)
                if task.id.hasPrefix("temp_") {
                    return true  // Always keep temp tasks
                }

                // For non-temp tasks, only keep if they have valid data AND aren't in server response
                let hasValidData = !task.title.trimmingCharacters(in: .whitespaces).isEmpty
                let notInServerResponse = !serverTaskIds.contains(task.id)

                return hasValidData && notInServerResponse
            }

            print("🔄 [TaskService] Merging tasks: \(uniqueTasks.count) from server + \(pendingTasks.count) pending")

            // Merge server tasks with pending tasks
            var mergedTasksDict: [String: Task] = [:]
            for task in uniqueTasks {
                mergedTasksDict[task.id] = task
            }
            for task in pendingTasks {
                mergedTasksDict[task.id] = task // Pending tasks override server
            }

            self.tasks = Array(mergedTasksDict.values).sorted { task1, task2 in
                // Sort by due date, then by creation date
                if let date1 = task1.dueDateTime, let date2 = task2.dueDateTime {
                    return date1 < date2
                }
                if task1.dueDateTime != nil {
                    return true
                }
                if task2.dueDateTime != nil {
                    return false
                }
                return (task1.createdAt ?? Date()) > (task2.createdAt ?? Date())
            }

            // Cache tasks in memory
            for task in self.tasks {
                cachedTasks[task.id] = task
            }

            // Save to Core Data for offline support (in background to avoid freezing)
            // This allows app to work offline by loading from cache
            _Concurrency.Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.saveTasksToCoreData(uniqueTasks)
                    print("✅ [TaskService] Saved \(uniqueTasks.count) tasks to Core Data")
                } catch {
                    print("⚠️ [TaskService] Failed to save to Core Data: \(error)")
                }
            }

            // Update app badge with due/overdue task count
            await badgeManager.updateBadge(with: self.tasks)

            print("✅ [TaskService] Synced \(self.tasks.count) unique tasks")

        } catch {
            errorMessage = error.localizedDescription
            print("⚠️ [TaskService] Sync failed (offline mode), using cached data: \(error)")
            // Don't throw - use cached data instead
            // Tasks are already loaded from cache in init()
            // Mark as loaded so UI doesn't block forever
            if !hasCompletedInitialLoad {
                hasCompletedInitialLoad = true
            }
        }
    }

    /// Fetch all tasks with batched processing for faster perceived load time
    /// Runs heavy processing on background thread to avoid blocking UI
    /// 1. Recent incomplete tasks (< 30 days)
    /// 2. Recent completed tasks (< 7 days)
    /// 3. Older incomplete tasks
    /// 4. Older completed tasks
    nonisolated func fetchAllTasksBatched() async throws {
        await MainActor.run { isLoading = true }
        await MainActor.run { errorMessage = nil }

        defer { _Concurrency.Task { @MainActor in isLoading = false } }

        do {
            // Fetch ALL tasks from server with automatic pagination
            print("📡 [TaskService] Fetching all user tasks (with pagination)...")
            let allServerTasks = try await apiClient.getAllTasks()
            print("✅ [TaskService] Fetched \(allServerTasks.count) tasks from server")

            // Debug: Check if API returns assigneeId
            let tasksWithAssignee = allServerTasks.filter { $0.assigneeId != nil }
            let tasksWithCreator = allServerTasks.filter { $0.creatorId != nil || $0.creator != nil }
            print("🔍 [TaskService] API returned \(allServerTasks.count) tasks:")
            print("  - Tasks with assigneeId: \(tasksWithAssignee.count)")
            print("  - Tasks with creatorId/creator: \(tasksWithCreator.count)")
            if allServerTasks.count > 0 {
                let sampleTask = allServerTasks[0]
                print("  - Sample task: '\(sampleTask.title)'")
                print("    - assigneeId: \(sampleTask.assigneeId ?? "nil")")
                print("    - creatorId: \(sampleTask.creatorId ?? "nil")")
                print("    - creator: \(sampleTask.creator != nil ? "exists" : "nil")")
            }

            // Get pending tasks (temp IDs not yet synced) - must access on MainActor
            let serverTaskIds = Set(allServerTasks.map { $0.id })
            let pendingTasks = await MainActor.run {
                self.tasks.filter { task in
                    if task.id.hasPrefix("temp_") {
                        return true
                    }
                    let hasValidData = !task.title.trimmingCharacters(in: .whitespaces).isEmpty
                    let notInServerResponse = !serverTaskIds.contains(task.id)
                    return hasValidData && notInServerResponse
                }
            }

            // Define time thresholds
            let now = Date()
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!

            // Categorize tasks into priority batches
            var batch1: [Task] = [] // Recent incomplete (highest priority)
            var batch2: [Task] = [] // Recent completed
            var batch3: [Task] = [] // Older incomplete
            var batch4: [Task] = [] // Older completed (lowest priority)

            for task in allServerTasks {
                let taskDate = task.updatedAt ?? task.createdAt ?? Date.distantPast
                let isRecent = taskDate >= thirtyDaysAgo

                if !task.completed {
                    if isRecent {
                        batch1.append(task) // Recent incomplete - SHOW FIRST
                    } else {
                        batch3.append(task) // Older incomplete
                    }
                } else {
                    if taskDate >= sevenDaysAgo {
                        batch2.append(task) // Recently completed
                    } else {
                        batch4.append(task) // Older completed
                    }
                }
            }

            print("📊 [TaskService] Task batches:")
            print("  Batch 1 (recent incomplete): \(batch1.count)")
            print("  Batch 2 (recent completed): \(batch2.count)")
            print("  Batch 3 (older incomplete): \(batch3.count)")
            print("  Batch 4 (older completed): \(batch4.count)")

            // Merge all batches in priority order (on background thread)
            print("⚡ [TaskService] Merging all batches...")
            let allTasks = batch1 + pendingTasks + batch2 + batch3 + batch4

            // Sort once on background thread
            let sortedTasks = sortTasks(allTasks)

            // Update UI on main thread (single update)
            await MainActor.run {
                self.tasks = sortedTasks
                print("✅ [TaskService] All batches merged: \(self.tasks.count) total tasks")

                // Cache tasks in memory
                for task in sortedTasks {
                    cachedTasks[task.id] = task
                }
            }

            // Save to Core Data for offline support (in background to avoid freezing)
            // Use batched processing to maintain performance
            _Concurrency.Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.saveTasksToCoreData(allServerTasks)
                    print("✅ [TaskService] Saved \(allServerTasks.count) tasks to Core Data for offline use")
                } catch {
                    print("⚠️ [TaskService] Failed to save to Core Data: \(error)")
                }
            }

            // Update app badge with due/overdue task count
            let currentTasks = await MainActor.run { self.tasks }
            await badgeManager.updateBadge(with: currentTasks)

            let finalCount = await MainActor.run { self.tasks.count }
            print("✅ [TaskService] Batched sync complete: \(finalCount) unique tasks (Core Data save running in background)")

        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
            print("⚠️ [TaskService] Batched sync failed (offline mode), using cached data: \(error)")
            // Don't throw - use cached data instead
            // Mark as loaded so UI doesn't block forever
            await MainActor.run {
                if !hasCompletedInitialLoad {
                    hasCompletedInitialLoad = true
                }
            }
        }
    }

    /// Sort tasks by priority (due date, then creation date)
    /// Pure function that can run on any thread
    private nonisolated func sortTasks(_ tasks: [Task]) -> [Task] {
        tasks.sorted { task1, task2 in
            if let date1 = task1.dueDateTime, let date2 = task2.dueDateTime {
                return date1 < date2
            }
            if task1.dueDateTime != nil {
                return true
            }
            if task2.dueDateTime != nil {
                return false
            }
            return (task1.createdAt ?? Date()) > (task2.createdAt ?? Date())
        }
    }

    // MARK: - Task Operations

    func fetchTask(id: String, forceRefresh: Bool = false) async throws -> Task {
        // Return cached if available and not forcing refresh
        if !forceRefresh, let cached = cachedTasks[id] {
            return cached
        }

        let task = try await apiClient.getTask(id: id)
        cachedTasks[id] = task

        // Update in the tasks array if it exists there
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index] = task
        }

        return task
    }

    func createTask(
        listIds: [String],
        title: String,
        description: String? = nil,
        priority: Int? = nil,
        whenDate: Date? = nil,     // The date (maps to backend 'when')
        whenTime: Date? = nil,     // The time (maps to backend 'dueDateTime', nil for all-day)
        assigneeId: String? = nil,
        isPrivate: Bool? = nil,
        repeating: String? = nil
    ) async throws -> Task {
        // OPTIMISTIC UPDATE: Create temporary task immediately
        let tempId = "temp_\(UUID().uuidString)"
        let currentUserId = AuthManager.shared.userId

        // Determine dueDateTime and isAllDay based on provided dates
        let dueDateTime: Date?
        let isAllDay: Bool
        if let whenTime = whenTime {
            // Timed task - use time
            dueDateTime = whenTime
            isAllDay = false
        } else if let whenDate = whenDate {
            // All-day task - use date
            dueDateTime = whenDate
            isAllDay = true
        } else {
            // No date set
            dueDateTime = nil
            isAllDay = false
        }

        let optimisticTask = Task(
            id: tempId,
            title: title,
            description: description ?? "",
            assigneeId: assigneeId,
            assignee: nil,
            creatorId: currentUserId, // Set creator to current user for permission checks
            creator: nil,
            dueDateTime: dueDateTime,
            isAllDay: isAllDay,
            reminderTime: nil,
            reminderSent: nil,
            reminderType: nil,
            repeating: repeating.flatMap { Task.Repeating(rawValue: $0) } ?? .never,
            repeatingData: nil,
            priority: priority.flatMap { Task.Priority(rawValue: $0) } ?? .none,
            lists: nil,
            listIds: listIds,
            isPrivate: isPrivate ?? true,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: Date(),
            updatedAt: Date(),
            originalTaskId: nil,
            sourceListId: nil
        )

        // Update UI immediately
        cachedTasks[tempId] = optimisticTask
        tasks.insert(optimisticTask, at: 0)
        print("⚡️ [TaskService] Optimistically created task: \(title)")

        // Save to CoreData with pending status for offline support (CRITICAL: await to ensure persistence)
        // This blocks until save completes, preventing data loss on force close
        do {
            try await saveTaskToCoreData(optimisticTask, syncStatus: "pending")
            print("✅ [TaskService] Persisted new task to CoreData")
        } catch {
            print("⚠️ [TaskService] Failed to save to CoreData, but task is in memory: \(error)")
        }

        // Make server call in background
        do {
            // CRITICAL: Filter out temp_ list IDs - server doesn't know about them
            // Tasks with temp list IDs will be synced later when lists get real IDs
            let serverListIds = listIds.filter { !$0.hasPrefix("temp_") }
            let hasTempListIds = listIds.count != serverListIds.count

            if hasTempListIds {
                print("⚠️ [TaskService] Filtering out temp_ list IDs for API call. Original: \(listIds), Filtered: \(serverListIds)")
            }

            // Send dueDateTime and isAllDay to backend
            // For all-day tasks: dueDateTime=date at UTC midnight, isAllDay=true
            // For timed tasks: dueDateTime=date+time, isAllDay=false
            let task = try await apiClient.createTask(
                title: title,
                listIds: serverListIds.isEmpty ? nil : serverListIds,  // Use filtered list IDs
                description: description,
                priority: priority,
                assigneeId: assigneeId,
                dueDateTime: dueDateTime,  // Already computed above based on whenDate/whenTime
                isAllDay: isAllDay,        // Already computed above
                isPrivate: isPrivate,
                repeating: repeating
            )

            // Replace temporary task with server response
            cachedTasks.removeValue(forKey: tempId)

            // CRITICAL: Preserve listIds from the original request
            // The server response may not include listIds (or may have them in a different format)
            // So we merge our original listIds with whatever the server returns
            var taskWithListIds = task
            var mergedListIds = task.listIds ?? []
            for originalListId in listIds {
                if !mergedListIds.contains(originalListId) {
                    mergedListIds.append(originalListId)
                }
            }
            taskWithListIds.listIds = mergedListIds

            cachedTasks[task.id] = taskWithListIds

            if let index = tasks.firstIndex(where: { $0.id == tempId }) {
                tasks[index] = taskWithListIds
            }

            // Update CoreData with server response (CRITICAL: await to ensure persistence)
            // If task has temp list IDs, mark as "pending_list_sync" so we can update later
            let syncStatus = hasTempListIds ? "pending_list_sync" : "synced"
            do {
                try await deleteTaskFromCoreData(tempId)  // Remove temp task
                try await saveTaskToCoreData(taskWithListIds, syncStatus: syncStatus)
                print("✅ [TaskService] Updated CoreData with server response")
            } catch {
                print("⚠️ [TaskService] Failed to update CoreData after task creation: \(error)")
            }

            print("✅ [TaskService] Server confirmed task: \(task.title)")

            // Track task creation
            AnalyticsService.shared.trackTaskCreated(AnalyticsService.TaskEventProps(
                taskId: task.id,
                listId: task.listIds?.first,
                hasDescription: !task.description.isEmpty,
                hasDueDate: task.dueDateTime != nil,
                hasReminder: task.reminderTime != nil,
                priority: task.priority.rawValue,
                isRepeating: task.repeating != .never
            ))

            // Schedule notification if task has due date
            if task.dueDateTime != nil {
                do {
                    try await notificationManager.scheduleNotification(for: task)
                } catch {
                    print("⚠️ [TaskService] Failed to schedule notification: \(error)")
                }
            }

            updatePendingOperationsCount()

            // Update app badge with new task count
            await badgeManager.updateBadge(with: self.tasks)

            return task
        } catch {
            // DON'T ROLLBACK: Keep task as "pending" for offline support
            print("⚠️ [TaskService] Failed to sync task to server, keeping as pending: \(error)")
            updatePendingOperationsCount()

            // Update badge even for pending tasks
            await badgeManager.updateBadge(with: self.tasks)

            // Return the optimistic task so UI shows it
            return optimisticTask
        }
    }

    func updateTask(
        taskId: String,
        title: String? = nil,
        description: String? = nil,
        priority: Int? = nil,
        completed: Bool? = nil,
        when: Date? = nil,  // DEPRECATED: Use dueDateTime instead
        whenTime: Date? = nil,  // DEPRECATED: Use isAllDay instead
        dueDateTime: Date? = nil,  // NEW: The due date/time
        isAllDay: Bool? = nil,  // NEW: All-day task flag
        assigneeId: String? = nil,
        repeating: String? = nil,
        repeatingData: CustomRepeatingPattern? = nil,
        repeatFrom: String? = nil,
        timerDuration: Int? = nil,
        lastTimerValue: String? = nil,
        listIds: [String]? = nil,
        task: Task? = nil  // Optional: provide task if not in cache (e.g., from featured lists)
    ) async throws -> Task {
        // OPTIMISTIC UPDATE: Store old task for rollback
        // First check cache, then provided task parameter (for featured/public list tasks)
        guard let originalTask = cachedTasks[taskId] ?? tasks.first(where: { $0.id == taskId }) ?? task else {
            throw NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }

        // Create optimistic updated task
        var optimisticTask = originalTask
        if let title = title { optimisticTask.title = title }
        if let description = description { optimisticTask.description = description }
        if let priority = priority { optimisticTask.priority = Task.Priority(rawValue: priority) ?? .none }
        if let completed = completed { optimisticTask.completed = completed }

        // Handle new dueDateTime + isAllDay OR legacy when/whenTime parameters
        if let dueDateTime = dueDateTime {
            optimisticTask.dueDateTime = (dueDateTime == Date.distantPast) ? nil : dueDateTime
        } else if let whenTime = whenTime {
            // Legacy: whenTime parameter (Date.distantPast means clear)
            optimisticTask.dueDateTime = (whenTime == Date.distantPast) ? nil : whenTime
            optimisticTask.isAllDay = false
        } else if let when = when {
            // Legacy: when parameter (date only, all-day)
            optimisticTask.dueDateTime = (when == Date.distantPast) ? nil : when
            optimisticTask.isAllDay = true
        }

        if let isAllDay = isAllDay {
            optimisticTask.isAllDay = isAllDay
        }
        // Handle assigneeId: empty string means unassign, nil means don't update
        if let assigneeId = assigneeId {
            optimisticTask.assigneeId = assigneeId.isEmpty ? nil : assigneeId
        }
        if let repeating = repeating { optimisticTask.repeating = Task.Repeating(rawValue: repeating) }
        if let repeatingData = repeatingData { optimisticTask.repeatingData = repeatingData }
        if let repeatFrom = repeatFrom { optimisticTask.repeatFrom = Task.RepeatFromMode(rawValue: repeatFrom) }
        if let timerDuration = timerDuration { optimisticTask.timerDuration = timerDuration }
        if let lastTimerValue = lastTimerValue { optimisticTask.lastTimerValue = lastTimerValue }
        if let listIds = listIds { optimisticTask.listIds = listIds }

        // CRITICAL: Update updatedAt to current time for optimistic update
        // This ensures completed tasks immediately pass the "recently completed" filter
        // Without this, tasks disappear when completed and reappear when server responds
        optimisticTask.updatedAt = Date()

        // Update UI immediately
        cachedTasks[taskId] = optimisticTask
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index] = optimisticTask
        } else {
            // Add to tasks array if not already there (e.g., featured list tasks)
            tasks.append(optimisticTask)
            print("➕ [TaskService] Added task to tasks array: \(optimisticTask.title)")
        }
        print("⚡️ [TaskService] Optimistically updated task: \(optimisticTask.title)")

        // Save to CoreData with pending status for offline support (CRITICAL: await to ensure persistence)
        // This blocks until save completes, preventing data loss on force close
        do {
            try await saveTaskToCoreData(optimisticTask, syncStatus: "pending")
            print("✅ [TaskService] Persisted update to CoreData")
        } catch {
            print("⚠️ [TaskService] Failed to save to CoreData, but task is updated in memory: \(error)")
        }

        // Make server call in background
        do {
            // Convert date/time to ISO8601 string for API
            // Backend expects:
            // - 'dueDateTime' = datetime (UTC midnight for all-day, specific time for timed)
            // - 'isAllDay' = boolean flag
            var dueDateTimeString: String?
            var isAllDayValue: Bool?

            // CRITICAL: Use UTC calendar for all-day task normalization
            var utcCalendar = Calendar.current
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!

            // Determine dueDateTime and isAllDay from either new or legacy parameters
            if let dueDateTime = dueDateTime {
                // New parameter path
                if dueDateTime == Date.distantPast {
                    // Clear due date
                    dueDateTimeString = ""
                    isAllDayValue = nil
                } else {
                    // Set due date (normalize to UTC midnight if all-day)
                    if let isAllDay = isAllDay, isAllDay {
                        let startOfDay = utcCalendar.startOfDay(for: dueDateTime)
                        dueDateTimeString = ISO8601DateFormatter().string(from: startOfDay)
                    } else {
                        dueDateTimeString = ISO8601DateFormatter().string(from: dueDateTime)
                    }
                    isAllDayValue = isAllDay
                }
            } else if let when = when, when == Date.distantPast,
                      let whenTime = whenTime, whenTime == Date.distantPast {
                // Legacy: Clear both date and time
                dueDateTimeString = ""
                isAllDayValue = nil
            } else if let when = when, when != Date.distantPast {
                // Legacy: Set date (all-day task)
                let startOfDay = utcCalendar.startOfDay(for: when)
                dueDateTimeString = ISO8601DateFormatter().string(from: startOfDay)

                // Check if time component is also being set
                if let whenTime = whenTime, whenTime != Date.distantPast {
                    // Time is set - timed task
                    dueDateTimeString = ISO8601DateFormatter().string(from: whenTime)
                    isAllDayValue = false
                } else if let whenTime = whenTime, whenTime == Date.distantPast {
                    // Explicitly clear time (all-day)
                    isAllDayValue = true
                } else {
                    // All-day by default
                    isAllDayValue = true
                }
            } else if let whenTime = whenTime, whenTime != Date.distantPast {
                // Legacy: Only time provided (timed task)
                dueDateTimeString = ISO8601DateFormatter().string(from: whenTime)
                isAllDayValue = false
            } else {
                // No date/time updates
                dueDateTimeString = nil
                isAllDayValue = nil
            }

            let updates = UpdateTaskRequest(
                title: title,
                description: description,
                priority: priority,
                repeating: repeating,
                repeatingData: repeatingData,
                repeatFrom: repeatFrom,
                isPrivate: nil,
                completed: completed,
                dueDateTime: dueDateTimeString,
                isAllDay: isAllDayValue,
                reminderTime: nil,
                reminderType: nil,
                listIds: listIds,
                assigneeId: assigneeId,
                timerDuration: timerDuration,
                lastTimerValue: lastTimerValue
            )

            print("🔄 [TaskService] Calling API client updateTask...")
            let task = try await apiClient.updateTask(id: taskId, updates: updates)
            print("✅ [TaskService] API response received:")
            print("  - title: \(task.title)")
            print("  - completed: \(task.completed)")
            print("  - repeating: \(task.repeating?.rawValue ?? "nil")")
            print("  - repeatingData: \(task.repeatingData != nil ? "present (unit: \(task.repeatingData?.unit ?? "nil"), interval: \(task.repeatingData?.interval ?? 0))" : "nil")")
            print("  - dueDateTime: \(task.dueDateTime?.description ?? "nil")")

            // Replace with server response
            print("🔄 [TaskService] Updating cached tasks...")
            cachedTasks[taskId] = task

            print("🔄 [TaskService] Updating tasks array...")
            if let index = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[index] = task
                print("✅ [TaskService] Updated task at index \(index)")
            } else {
                // Add to tasks array if not already there (e.g., featured list tasks)
                tasks.append(task)
                print("➕ [TaskService] Added task to tasks array from server response: \(task.title)")
            }

            // Update CoreData with synced status (CRITICAL: await to ensure persistence)
            print("🔄 [TaskService] Saving to CoreData...")
            do {
                try await saveTaskToCoreData(task, syncStatus: "synced")
                print("✅ [TaskService] CoreData save complete")
            } catch {
                print("⚠️ [TaskService] Failed to update CoreData after task update: \(error)")
                print("⚠️ [TaskService] CoreData error details: \(String(describing: error))")
            }

            print("✅ [TaskService] Server confirmed update: \(task.title)")

            // Track completion status changes
            if let completed = completed, completed != originalTask.completed {
                let props = AnalyticsService.TaskEventProps(
                    taskId: task.id,
                    listId: task.listIds?.first,
                    hasDescription: !task.description.isEmpty,
                    hasDueDate: task.dueDateTime != nil,
                    hasReminder: task.reminderTime != nil,
                    priority: task.priority.rawValue,
                    isRepeating: task.repeating != .never
                )
                if completed {
                    AnalyticsService.shared.trackTaskCompleted(props, source: "checkbox")
                } else {
                    AnalyticsService.shared.trackTaskUncompleted(props)
                }
            }

            // Track task edits (non-completion changes)
            var fieldsChanged: [String] = []
            if title != nil && title != originalTask.title { fieldsChanged.append("title") }
            if description != nil && description != originalTask.description { fieldsChanged.append("description") }
            if priority != nil && priority != originalTask.priority.rawValue { fieldsChanged.append("priority") }
            if dueDateTime != nil || when != nil || whenTime != nil { fieldsChanged.append("dueDate") }
            if assigneeId != nil && assigneeId != originalTask.assigneeId { fieldsChanged.append("assignee") }
            if listIds != nil { fieldsChanged.append("lists") }
            if repeating != nil && repeating != originalTask.repeating?.rawValue { fieldsChanged.append("repeating") }

            if !fieldsChanged.isEmpty {
                let props = AnalyticsService.TaskEventProps(
                    taskId: task.id,
                    listId: task.listIds?.first
                )
                AnalyticsService.shared.trackTaskEdited(props, fieldsChanged: fieldsChanged)
            }

            // Handle notification updates
            if let completed = completed, completed {
                // Cancel notification if task is completed
                await notificationManager.cancelNotification(for: taskId)
            } else if when != nil || whenTime != nil || task.dueDateTime != nil {
                // Reschedule notification if date or time changed or still exists
                do {
                    try await notificationManager.rescheduleNotification(for: task)
                } catch {
                    print("⚠️ [TaskService] Failed to reschedule notification: \(error)")
                }
            }

            updatePendingOperationsCount()

            // Update app badge after task update
            await badgeManager.updateBadge(with: self.tasks)

            return task
        } catch {
            // DON'T ROLLBACK: Keep task as "pending" for offline support
            print("⚠️ [TaskService] Failed to sync update to server, keeping as pending: \(error)")
            updatePendingOperationsCount()

            // Update badge even for pending updates
            await badgeManager.updateBadge(with: self.tasks)

            // Return the optimistic task so UI shows it
            return optimisticTask
        }
    }

    func completeTask(id: String, completed: Bool, task: Task? = nil) async throws -> Task {
        // Get the current task - prefer the passed task (what user sees on screen) over cache
        // The cache might be stale if the task was updated on web
        guard let currentTask = task ?? cachedTasks[id] ?? tasks.first(where: { $0.id == id }) else {
            throw NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }

        // Handle repeating task roll-forward locally (offline support)
        // Only process when marking as complete (not un-complete) and task is repeating
        if completed && !currentTask.completed,
           let repeating = currentTask.repeating,
           repeating != .never {

            print("🔄 [TaskService] Rolling forward repeating task: \(currentTask.title)")
            print("  - Current dueDateTime: \(currentTask.dueDateTime?.description ?? "nil")")
            print("  - repeatFrom: \(currentTask.repeatFrom?.rawValue ?? "nil")")

            // Calculate next due date
            let (nextDueDate, shouldTerminate) = calculateNextOccurrence(for: currentTask)

            if shouldTerminate {
                print("🏁 [TaskService] Repeating series terminated")
                // Series ended - keep completed, clear repeating
                return try await updateTask(
                    taskId: id,
                    completed: true,
                    repeating: "never",
                    repeatingData: nil,
                    task: task
                )
            } else if let nextDue = nextDueDate {
                print("📅 [TaskService] Next occurrence: \(nextDue)")
                // Roll forward - set completed false, update due date
                _ = (currentTask.occurrenceCount ?? 0) + 1
                return try await updateTask(
                    taskId: id,
                    completed: false,
                    dueDateTime: nextDue,
                    isAllDay: currentTask.isAllDay,
                    task: task
                )
            }
        }

        // Non-repeating task or un-completing - use normal update
        return try await updateTask(taskId: id, completed: completed, task: task)
    }

    /// Calculate the next occurrence date for a repeating task
    private func calculateNextOccurrence(for task: Task) -> (nextDate: Date?, shouldTerminate: Bool) {
        let completionDate = Date()
        let currentDueDate = task.dueDateTime
        let repeatFrom = task.repeatFrom ?? .COMPLETION_DATE
        let currentOccurrenceCount = task.occurrenceCount ?? 0
        let newOccurrenceCount = currentOccurrenceCount + 1

        // Determine anchor date based on repeat mode
        // CRITICAL: Use UTC calendar for all date/time operations to match web behavior
        // All-day tasks are stored as UTC midnight (e.g., 2026-01-06T00:00:00Z)
        // Using local calendar would extract incorrect time (e.g., 4 PM PST for UTC midnight)
        // which causes the anchor date to shift by a day, making next occurrence 2 days ahead
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        let anchorDate: Date
        if let dueDate = currentDueDate {
            if repeatFrom == .DUE_DATE {
                anchorDate = dueDate
            } else {
                // COMPLETION_DATE mode: Use completion date with original due time
                if task.isAllDay {
                    // CRITICAL FIX for all-day tasks:
                    // Extract the LOCAL date from completion (not UTC date)
                    // This fixes the bug where completing at 9pm PST (= 5am UTC next day)
                    // would extract Jan 6 UTC instead of Jan 5 local
                    //
                    // Example: Task due "Jan 5" (stored as Jan 5, 00:00 UTC)
                    // User completes at Jan 5, 9pm PST = Jan 6, 5am UTC
                    // Wrong: UTC date = Jan 6, next = Jan 7
                    // Right: Local date = Jan 5, next = Jan 6
                    let localCalendar = Calendar.current
                    let localDateComponents = localCalendar.dateComponents([.year, .month, .day], from: completionDate)

                    // Create anchor as the LOCAL date at UTC midnight (how all-day tasks are stored)
                    var utcComponents = DateComponents()
                    utcComponents.year = localDateComponents.year
                    utcComponents.month = localDateComponents.month
                    utcComponents.day = localDateComponents.day
                    utcComponents.hour = 0
                    utcComponents.minute = 0
                    utcComponents.second = 0
                    utcComponents.timeZone = TimeZone(identifier: "UTC")
                    anchorDate = utcCalendar.date(from: utcComponents) ?? dueDate
                } else {
                    // Timed tasks: Use UTC date from completion with time from due date
                    let dateComponents = utcCalendar.dateComponents([.year, .month, .day], from: completionDate)
                    let timeComponents = utcCalendar.dateComponents([.hour, .minute, .second], from: dueDate)
                    var combined = DateComponents()
                    combined.year = dateComponents.year
                    combined.month = dateComponents.month
                    combined.day = dateComponents.day
                    combined.hour = timeComponents.hour
                    combined.minute = timeComponents.minute
                    combined.second = timeComponents.second
                    combined.timeZone = TimeZone(identifier: "UTC")
                    anchorDate = utcCalendar.date(from: combined) ?? completionDate
                }
            }
        } else {
            anchorDate = completionDate
        }

        // Calculate next date based on pattern
        // CRITICAL: Use UTC calendar for all date arithmetic to match web behavior
        // Using local calendar causes timezone issues, especially for all-day tasks
        // where the UTC midnight date may differ from the local date
        var nextDate: Date?

        if task.repeating == .custom, let pattern = task.repeatingData {
            // Custom pattern
            let interval = pattern.interval ?? 1

            switch pattern.unit {
            case "days":
                // Use UTC-safe day addition (24 hours in milliseconds)
                nextDate = anchorDate.addingTimeInterval(Double(interval) * 24 * 60 * 60)
            case "weeks":
                // Use UTC-safe week addition (7 * 24 hours in milliseconds)
                nextDate = anchorDate.addingTimeInterval(Double(interval * 7) * 24 * 60 * 60)
            case "months":
                nextDate = utcCalendar.date(byAdding: .month, value: interval, to: anchorDate)
            case "years":
                nextDate = utcCalendar.date(byAdding: .year, value: interval, to: anchorDate)
            default:
                nextDate = anchorDate.addingTimeInterval(Double(interval) * 24 * 60 * 60)
            }

            // Check end conditions
            if pattern.endCondition == "after_occurrences",
               let endAfter = pattern.endAfterOccurrences,
               newOccurrenceCount >= endAfter {
                return (nil, true)
            }

            if pattern.endCondition == "until_date",
               let endDate = pattern.endUntilDate,
               let next = nextDate,
               next > endDate {
                return (nil, true)
            }
        } else {
            // Simple patterns - use UTC-safe date arithmetic
            switch task.repeating {
            case .daily:
                // Add exactly 24 hours (avoids local calendar timezone issues)
                nextDate = anchorDate.addingTimeInterval(24 * 60 * 60)
            case .weekly:
                // Add exactly 7 days (168 hours)
                nextDate = anchorDate.addingTimeInterval(7 * 24 * 60 * 60)
            case .monthly:
                nextDate = utcCalendar.date(byAdding: .month, value: 1, to: anchorDate)
            case .yearly:
                nextDate = utcCalendar.date(byAdding: .year, value: 1, to: anchorDate)
            default:
                break
            }
        }

        // Preserve time from original due date if available (for timed tasks only)
        // Use UTC calendar to avoid timezone conversion issues
        if let next = nextDate, let original = currentDueDate, !task.isAllDay {
            var utcCal = Calendar.current
            utcCal.timeZone = TimeZone(identifier: "UTC")!
            let timeComponents = utcCal.dateComponents([.hour, .minute, .second], from: original)
            let dateComponents = utcCal.dateComponents([.year, .month, .day], from: next)
            var combined = DateComponents()
            combined.year = dateComponents.year
            combined.month = dateComponents.month
            combined.day = dateComponents.day
            combined.hour = timeComponents.hour
            combined.minute = timeComponents.minute
            combined.second = timeComponents.second
            combined.timeZone = TimeZone(identifier: "UTC")
            nextDate = utcCal.date(from: combined)
        }

        return (nextDate, false)
    }

    func updateTaskLists(taskId: String, listIds: [String]) async throws -> Task {
        return try await updateTask(taskId: taskId, listIds: listIds)
    }

    func deleteTask(id: String, task: Task? = nil) async throws {
        // OPTIMISTIC UPDATE: Store task for potential recovery
        // Check cache first, then provided task parameter (for featured/public list tasks)
        guard let deletedTask = cachedTasks[id] ?? tasks.first(where: { $0.id == id }) ?? task else {
            throw NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }

        // Remove from UI immediately
        cachedTasks.removeValue(forKey: id)
        tasks.removeAll { $0.id == id }
        print("⚡️ [TaskService] Optimistically deleted task: \(deletedTask.title)")

        // Mark as deleted in CoreData for offline support (CRITICAL: await to ensure persistence)
        // This blocks until save completes, preventing data loss on force close
        do {
            var deletedTaskCopy = deletedTask
            deletedTaskCopy.completed = true  // Mark as completed for now
            try await saveTaskToCoreData(deletedTaskCopy, syncStatus: "pending_delete")
            print("✅ [TaskService] Persisted deletion to CoreData")
        } catch {
            print("⚠️ [TaskService] Failed to save deletion to CoreData, but task is removed from memory: \(error)")
        }

        // Cancel notification
        await notificationManager.cancelNotification(for: id)

        // Update app badge after task deletion
        await badgeManager.updateBadge(with: self.tasks)

        // Make server call in background
        do {
            try await apiClient.deleteTask(id: id)
            print("✅ [TaskService] Server confirmed deletion: \(id)")

            // Track task deletion
            AnalyticsService.shared.trackTaskDeleted(AnalyticsService.TaskEventProps(
                taskId: deletedTask.id,
                listId: deletedTask.listIds?.first
            ))

            // Remove from CoreData after successful deletion (CRITICAL: await to ensure persistence)
            do {
                try await deleteTaskFromCoreData(id)
                updatePendingOperationsCount()
                print("✅ [TaskService] Removed from CoreData after successful deletion")
            } catch {
                print("⚠️ [TaskService] Failed to remove from CoreData after deletion: \(error)")
            }
        } catch {
            // DON'T ROLLBACK: Keep task as "pending_delete" for offline support
            print("⚠️ [TaskService] Failed to sync deletion to server, keeping as pending: \(error)")
            updatePendingOperationsCount()
            // Badge already updated above after optimistic delete
            // Don't re-add to UI, let it stay deleted locally
        }
    }

    func copyTask(
        id: String,
        targetListId: String?,
        includeComments: Bool = false,
        preserveDueDate: Bool = false,
        preserveAssignee: Bool = false
    ) async throws -> Task {
        // Fetch the original task
        print("📋 [TaskService] Fetching original task to copy: \(id)")
        let originalTask = try await fetchTask(id: id)

        // Determine target list IDs
        // Allow empty listIds for "My Tasks (only)" - tasks without lists are valid
        let listIds: [String]
        if let targetListId = targetListId, !targetListId.isEmpty {
            // Specific list selected
            listIds = [targetListId]
        } else if targetListId == nil || targetListId == "" {
            // "My Tasks (only)" selected - use empty array (no lists)
            listIds = []
        } else if let originalListIds = originalTask.listIds, !originalListIds.isEmpty {
            // Fallback: Use original list IDs if available
            listIds = originalListIds
        } else {
            // Default: No lists (My Tasks only)
            listIds = []
        }

        // Determine assignee for copied task
        // When copying to a list: make task unassigned
        // When copying to "My Tasks (only)" (no lists): assign to current user
        let copyAssigneeId: String?
        if listIds.isEmpty {
            // "My Tasks (only)" - always assign to current user so it appears in My Tasks
            copyAssigneeId = AuthManager.shared.userId
            print("📋 [TaskService] Copying to My Tasks (only) - assigning to current user")
        } else {
            // Copying to a list - make task unassigned
            copyAssigneeId = nil
            print("📋 [TaskService] Copying to list - making task unassigned")
        }

        // Copy the task using createTask (no [copy] suffix, just copy as-is)
        print("📋 [TaskService] Creating copy of task in list(s): \(listIds)")
        let copiedTask = try await createTask(
            listIds: listIds,
            title: originalTask.title,
            description: originalTask.description,
            priority: originalTask.priority.rawValue,
            whenDate: preserveDueDate ? (originalTask.isAllDay ? originalTask.dueDateTime : nil) : nil,
            whenTime: preserveDueDate ? (!originalTask.isAllDay ? originalTask.dueDateTime : nil) : nil,
            assigneeId: copyAssigneeId,
            isPrivate: originalTask.isPrivate,
            repeating: originalTask.repeating?.rawValue
        )

        print("✅ [TaskService] Task copied successfully: \(copiedTask.title)")

        // Copy comments if requested
        if includeComments {
            do {
                // Fetch comments from the original task
                print("📋 [TaskService] Fetching comments for task: \(id)")
                let comments = try await CommentService.shared.fetchComments(taskId: id)

                if !comments.isEmpty {
                    // Filter out system comments (authorId is nil)
                    let userComments = comments.filter { $0.authorId != nil }

                    if !userComments.isEmpty {
                        print("📋 [TaskService] Copying \(userComments.count) user comments...")

                        for comment in userComments {
                            do {
                                // Preserve the original comment author when copying
                                _ = try await CommentService.shared.createComment(
                                    taskId: copiedTask.id,
                                    content: comment.content,
                                    type: comment.type,
                                    authorId: comment.authorId
                                )
                            } catch {
                                print("⚠️ [TaskService] Failed to copy comment: \(error) ")
                                // Continue copying other comments even if one fails
                            }
                        }

                        print("✅ [TaskService] Comments copied")
                    } else {
                        print("ℹ️ [TaskService] No user comments to copy")
                    }
                } else {
                    print("ℹ️ [TaskService] No comments to copy")
                }
            } catch {
                print("⚠️ [TaskService] Failed to fetch comments for copying: \(error)")
                // Don't fail the entire copy operation if comment copying fails
            }
        }

        return copiedTask
    }

    // MARK: - Filtering

    func getTasksForList(_ listId: String) -> [Task] {
        return tasks.filter { task in
            task.listIds?.contains(listId) == true ||
            task.lists?.contains(where: { $0.id == listId }) == true
        }
    }

    func getCompletedTasks() -> [Task] {
        return tasks.filter { $0.completed }
    }

    func getIncompleteTasks() -> [Task] {
        return tasks.filter { !$0.completed }
    }

    // MARK: - CoreData Persistence

    /// Save multiple tasks to CoreData with optimized batch operations
    private func saveTasksToCoreData(_ tasks: [Task]) async throws {
        print("💾 [TaskService] Saving \(tasks.count) tasks to Core Data...")

        try await coreDataManager.saveInBackground { context in
            // Fetch all existing tasks in ONE batch query instead of 394 individual queries
            let taskIds = tasks.map { $0.id }
            let fetchRequest = CDTask.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", taskIds)
            let existingTasks = try context.fetch(fetchRequest)

            // Create dictionary for O(1) lookup
            var existingTasksDict = [String: CDTask]()
            for cdTask in existingTasks {
                existingTasksDict[cdTask.id] = cdTask
            }

            print("💾 [TaskService] Found \(existingTasks.count) existing tasks, creating \(tasks.count - existingTasks.count) new tasks")

            // Update or create tasks
            for task in tasks {
                let cdTask = existingTasksDict[task.id] ?? CDTask(context: context)
                cdTask.id = task.id
                cdTask.update(from: task)
                cdTask.syncStatus = "synced"
                cdTask.lastSyncedAt = Date()
            }

            print("💾 [TaskService] Core Data save completed")
        }

        print("✅ [TaskService] Successfully saved \(tasks.count) tasks to Core Data")
    }

    /// Save single task to CoreData with sync status
    private func saveTaskToCoreData(_ task: Task, syncStatus: String) async throws {
        try await coreDataManager.saveInBackground { context in
            let cdTask = try CDTask.fetchById(task.id, context: context) ?? CDTask(context: context)
            cdTask.id = task.id
            cdTask.update(from: task)
            cdTask.syncStatus = syncStatus
            if syncStatus == "synced" {
                cdTask.lastSyncedAt = Date()
            }
        }
    }

    /// Delete task from CoreData
    private func deleteTaskFromCoreData(_ id: String) async throws {
        try await coreDataManager.saveInBackground { context in
            if let cdTask = try CDTask.fetchById(id, context: context) {
                context.delete(cdTask)
            }
        }
    }

    /// Update pending operations count
    private func updatePendingOperationsCount() {
        do {
            let context = coreDataManager.viewContext
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "syncStatus == %@ OR syncStatus == %@", "pending", "pending_delete")
            let count = try context.count(for: request)
            pendingOperationsCount = count
            print("📊 [TaskService] Pending operations: \(count)")

            // Also update failed count
            updateFailedOperationsCount()
        } catch {
            print("❌ [TaskService] Failed to count pending operations: \(error)")
        }
    }

    /// Update failed operations count
    private func updateFailedOperationsCount() {
        do {
            let context = coreDataManager.viewContext
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "syncStatus == %@", "failed")
            let count = try context.count(for: request)
            failedOperationsCount = count
        } catch {
            print("❌ [TaskService] Failed to count failed operations: \(error)")
        }
    }

    /// Retry all failed operations
    func retryFailedOperations() async {
        print("🔄 [TaskService] Retrying failed operations...")

        do {
            try await coreDataManager.saveInBackground { context in
                let failedTasks = try CDTask.fetchFailedTasks(context: context)
                for task in failedTasks {
                    task.syncAttempts = 0
                    task.syncStatus = "pending"
                    task.lastSyncError = nil
                }
                print("📊 [TaskService] Reset \(failedTasks.count) failed tasks to pending")
            }

            // Trigger sync
            try await syncPendingOperations()
        } catch {
            print("❌ [TaskService] Failed to retry operations: \(error)")
        }
    }

    // MARK: - Cache Management

    /// Clear all in-memory task data (used on logout)
    func clearCache() {
        tasks = []
        cachedTasks = [:]
        pendingOperationsCount = 0
        print("🗑️ [TaskService] In-memory task cache cleared")
    }

    /// Update a single task in the cache (used when bypassing normal update flow)
    func updateTaskInCache(_ task: Task) {
        cachedTasks[task.id] = task
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        }
        print("📝 [TaskService] Updated task in cache: \(task.title)")
    }

    /// Update tasks from sync manager (used by list-based sync)
    /// Heavy sorting is done in background to avoid blocking main thread
    func updateTasksFromSync(_ newTasks: [Task]) {
        // Get pending local tasks (temp IDs) - quick filter
        let pendingTasks = self.tasks.filter { $0.id.hasPrefix("temp_") }

        // Process heavy sorting in background to keep UI responsive
        _Concurrency.Task {
            let sortedTasks = await Self.mergeAndSortTasksInBackground(
                newTasks: newTasks,
                pendingTasks: pendingTasks
            )

            // Update UI on main actor (quick assignment)
            self.tasks = sortedTasks

            // Cache tasks in memory
            for task in sortedTasks {
                self.cachedTasks[task.id] = task
            }

            print("✅ [TaskService] Updated \(self.tasks.count) tasks from sync")

            // Update app badge after sync
            await self.badgeManager.updateBadge(with: self.tasks)

            // Save to CoreData in background for offline support
            _Concurrency.Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    let tasksToSave = await MainActor.run { Array(self.tasks.filter { !$0.id.hasPrefix("temp_") }) }
                    try await self.saveTasksToCoreData(tasksToSave)
                    print("✅ [TaskService] Saved \(tasksToSave.count) synced tasks to CoreData for offline use")
                } catch {
                    print("⚠️ [TaskService] Failed to save synced tasks to CoreData: \(error)")
                }
            }
        }
    }

    /// Merge and sort tasks in background to avoid blocking main thread
    private static nonisolated func mergeAndSortTasksInBackground(
        newTasks: [Task],
        pendingTasks: [Task]
    ) async -> [Task] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Merge server tasks with pending tasks using dictionary
                var mergedDict: [String: Task] = [:]
                for task in newTasks {
                    mergedDict[task.id] = task
                }
                for task in pendingTasks {
                    mergedDict[task.id] = task // Pending tasks override server
                }

                // Sort by due date, then by creation date
                let sorted = Array(mergedDict.values).sorted { task1, task2 in
                    if let date1 = task1.dueDateTime, let date2 = task2.dueDateTime {
                        return date1 < date2
                    }
                    if task1.dueDateTime != nil {
                        return true
                    }
                    if task2.dueDateTime != nil {
                        return false
                    }
                    return (task1.createdAt ?? Date()) > (task2.createdAt ?? Date())
                }

                continuation.resume(returning: sorted)
            }
        }
    }

    // MARK: - Offline Sync

    /// Sync all pending operations to server
    func syncPendingOperations() async throws {
        guard !isSyncingPendingOperations else {
            print("⏳ [TaskService] Sync already in progress")
            return
        }

        isSyncingPendingOperations = true
        defer { isSyncingPendingOperations = false }

        print("🔄 [TaskService] Starting sync of pending operations...")
        print("📊 [TaskService] Before sync: \(tasks.count) tasks in memory, \(cachedTasks.count) in cache")

        let context = coreDataManager.viewContext

        // Fetch all pending tasks
        let request = CDTask.fetchRequest()
        request.predicate = NSPredicate(format: "syncStatus == %@ OR syncStatus == %@", "pending", "pending_delete")
        let pendingTasks = try context.fetch(request)

        print("📤 [TaskService] Found \(pendingTasks.count) pending operations")

        var syncedCount = 0
        var failedCount = 0

        for cdTask in pendingTasks {
            do {
                if cdTask.syncStatus == "pending_delete" {
                    // Handle pending deletions
                    try await apiClient.deleteTask(id: cdTask.id)
                    try await deleteTaskFromCoreData(cdTask.id)
                    print("✅ [TaskService] Synced deletion: \(cdTask.id)")
                } else {
                    // Handle pending creates/updates
                    let task = cdTask.toDomainModel()

                    // Check if task exists on server by attempting update first
                    // If it fails with 404, create it instead
                    do {
                        // Convert dueDateTime to ISO8601 string for API
                        let dueDateTimeString: String? = task.dueDateTime.map { date in
                            ISO8601DateFormatter().string(from: date)
                        }

                        let updates = UpdateTaskRequest(
                            title: task.title,
                            description: task.description,
                            priority: task.priority.rawValue,
                            repeating: task.repeating?.rawValue,
                            repeatingData: nil,
                            isPrivate: task.isPrivate,
                            completed: task.completed,
                            dueDateTime: dueDateTimeString,  // Pass ISO8601 datetime string
                            isAllDay: task.isAllDay,  // Pass isAllDay flag
                            reminderTime: nil,
                            reminderType: nil,
                            listIds: task.listIds,
                            assigneeId: task.assigneeId
                        )

                        let updatedTask = try await apiClient.updateTask(id: task.id, updates: updates)

                        // Update with server response
                        try await saveTaskToCoreData(updatedTask, syncStatus: "synced")

                        // CRITICAL: Update in-memory arrays to match CoreData
                        cachedTasks[updatedTask.id] = updatedTask
                        if let index = tasks.firstIndex(where: { $0.id == updatedTask.id }) {
                            tasks[index] = updatedTask
                        } else {
                            // Task not in array - add it (defensive)
                            tasks.insert(updatedTask, at: 0)
                            print("⚠️ [TaskService] Task was missing from in-memory array, added it")
                        }

                        print("✅ [TaskService] Synced update: \(updatedTask.title)")
                    } catch {
                        // If update failed (likely 404), try creating instead
                        if task.id.hasPrefix("temp_") {
                            // CRITICAL: Filter out temp_ list IDs and resolve any mapped IDs
                            let resolvedListIds = resolveListIds(task.listIds ?? [])
                            let serverListIds = resolvedListIds.filter { !$0.hasPrefix("temp_") }

                            let createdTask = try await apiClient.createTask(
                                title: task.title,
                                listIds: serverListIds.isEmpty ? nil : serverListIds,  // Filter temp_ IDs
                                description: task.description.isEmpty ? nil : task.description,
                                priority: task.priority.rawValue,
                                assigneeId: task.assigneeId,
                                dueDateTime: task.dueDateTime,
                                isAllDay: task.isAllDay,
                                isPrivate: task.isPrivate,
                                repeating: task.repeating?.rawValue
                            )

                            // Replace temp task with server task
                            try await deleteTaskFromCoreData(task.id)
                            try await saveTaskToCoreData(createdTask, syncStatus: "synced")

                            // Update in-memory arrays
                            cachedTasks.removeValue(forKey: task.id)
                            cachedTasks[createdTask.id] = createdTask
                            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                tasks[index] = createdTask
                            }

                            print("✅ [TaskService] Synced creation: \(createdTask.title)")
                        } else {
                            throw error
                        }
                    }
                }

                syncedCount += 1
            } catch {
                print("❌ [TaskService] Failed to sync task \(cdTask.id): \(error)")
                failedCount += 1
                // Mark as failed for retry later
                cdTask.syncStatus = "failed"
                try? coreDataManager.save()
            }
        }

        updatePendingOperationsCount()
        print("✅ [TaskService] Sync complete: \(syncedCount) synced, \(failedCount) failed")
        print("📊 [TaskService] After sync: \(tasks.count) tasks in memory, \(cachedTasks.count) in cache")

        // NOTE: Don't call fetchAllTasks() here - sync loop already updated in-memory tasks
        // Calling fetchAllTasks() would replace local tasks with server tasks and could lose data
    }

    // MARK: - Temp List ID Resolution

    /// Called by ListService when a temp list ID gets its real server ID
    /// Updates all tasks that reference the temp ID to use the real ID
    func onListSynced(tempListId: String, realListId: String) async {
        print("🔄 [TaskService] List synced: \(tempListId) → \(realListId)")

        // Store the mapping for future reference
        tempListIdMapping[tempListId] = realListId

        // Find all tasks that have the temp list ID
        var tasksToUpdate: [Task] = []
        for task in tasks {
            if let listIds = task.listIds, listIds.contains(tempListId) {
                tasksToUpdate.append(task)
            }
        }

        if tasksToUpdate.isEmpty {
            print("ℹ️ [TaskService] No tasks found with temp list ID: \(tempListId)")
            return
        }

        print("📝 [TaskService] Found \(tasksToUpdate.count) tasks to update with new list ID")

        // Update each task
        for task in tasksToUpdate {
            // Replace temp ID with real ID in listIds
            var updatedListIds = task.listIds ?? []
            updatedListIds = updatedListIds.map { $0 == tempListId ? realListId : $0 }

            // Remove any duplicates (in case real ID was already there)
            updatedListIds = Array(Set(updatedListIds))

            do {
                // Update task on server with new list ID
                let updatedTask = try await updateTask(taskId: task.id, listIds: updatedListIds)
                print("✅ [TaskService] Updated task '\(updatedTask.title)' with real list ID")
            } catch {
                print("⚠️ [TaskService] Failed to update task '\(task.title)' with real list ID: \(error)")
                // Task stays with the updated local listIds, will retry on next sync
            }
        }
    }

    /// Resolve any temp list IDs in the given array using stored mappings
    private func resolveListIds(_ listIds: [String]) -> [String] {
        return listIds.map { listId in
            if listId.hasPrefix("temp_"), let realId = tempListIdMapping[listId] {
                return realId
            }
            return listId
        }
    }
}
