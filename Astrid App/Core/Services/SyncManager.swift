import Foundation
import Combine

/// Manages incremental syncing between iOS app and backend
/// Tracks last sync timestamp and only fetches changes
/// Now uses modern OAuth + RESTful API v1
@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var hasCompletedInitialSync = false  // Track if initial network sync is done

    // Per-entity sync timestamps for incremental sync
    @Published var lastTaskSyncDate: Date?
    @Published var lastListSyncDate: Date?
    @Published var lastCommentSyncDate: Date?

    private let apiClient = AstridAPIClient.shared
    private let taskService = TaskService.shared
    private let listService = ListService.shared // Temp: for legacy methods
    private let commentService = CommentService.shared
    private let listMemberService = ListMemberService.shared
    private let reminderSettings = ReminderSettings.shared

    private let lastSyncKey = "last_sync_timestamp"
    private let lastTaskSyncKey = "last_task_sync_timestamp"
    private let lastListSyncKey = "last_list_sync_timestamp"
    private let lastCommentSyncKey = "last_comment_sync_timestamp"

    private init() {
        // Load last sync timestamps
        if let timestamp = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = timestamp
        }
        if let timestamp = UserDefaults.standard.object(forKey: lastTaskSyncKey) as? Date {
            lastTaskSyncDate = timestamp
        }
        if let timestamp = UserDefaults.standard.object(forKey: lastListSyncKey) as? Date {
            lastListSyncDate = timestamp
        }
        if let timestamp = UserDefaults.standard.object(forKey: lastCommentSyncKey) as? Date {
            lastCommentSyncDate = timestamp
        }
    }

    // MARK: - Full Sync

    /// Perform a full sync (initial sync or after long time)
    /// - Parameter includeUserTasks: If true, also fetches user tasks (heavy operation, use sparingly)
    func performFullSync(includeUserTasks: Bool = false) async throws {
        isSyncing = true
        defer { isSyncing = false }

        print("🔄 [SyncManager] Starting full sync with OAuth + API v1...")

        do {
            // Fetch all lists using new API (network call - doesn't block main thread)
            print("📋 [SyncManager] Fetching lists via API v1...")
            let lists = try await apiClient.getLists()
            print("✅ [SyncManager] Lists fetched: \(lists.count)")

            // Get pending lists before processing (quick operation)
            let pendingLists = listService.lists.filter { $0.id.hasPrefix("temp_") }

            // Process lists in background to avoid blocking main thread
            let mergedLists = await Self.processListsInBackground(
                serverLists: lists,
                pendingLists: pendingLists
            )

            // Update UI on main actor (quick assignment)
            listService.lists = mergedLists
            print("✅ [SyncManager] Lists synced: \(listService.lists.count)")

            // Cache user images in background (doesn't block UI)
            _Concurrency.Task.detached(priority: .utility) {
                await UserImageCache.shared.cacheFromLists(lists)
            }

            // Fetch all tasks using new API v1 (network call - doesn't block main thread)
            print("📝 [SyncManager] Fetching all tasks via API v1 (with pagination)...")
            let tasks: [Task]
            do {
                tasks = try await apiClient.getAllTasks()
                print("  ✅ Fetched \(tasks.count) tasks from API v1")
            } catch {
                print("  ⚠️ Failed to fetch tasks: \(error)")
                throw error
            }

            // Process tasks in background to avoid blocking main thread
            let currentUserId = AuthManager.shared.userId
            let (uniqueTasks, validationError) = await Self.processTasksInBackground(
                serverTasks: tasks,
                currentUserId: currentUserId
            )

            // Handle validation error if any
            if let error = validationError {
                taskService.clearCache()
                listService.clearCache()
                hasCompletedInitialSync = false
                throw error
            }

            print("✅ [SyncManager] Total unique tasks: \(uniqueTasks.count)")

            // Update TaskService with the fetched tasks
            taskService.updateTasksFromSync(uniqueTasks)
            print("✅ [SyncManager] Tasks synced: \(taskService.tasks.count)")

            // Cache user images in background (doesn't block UI)
            _Concurrency.Task.detached(priority: .utility) {
                await UserImageCache.shared.cacheFromTasks(uniqueTasks)
            }

            // Sync pending comments (local-first offline support)
            print("🔄 [SyncManager] Syncing pending comments...")
            do {
                try await commentService.syncPendingComments()
                print("✅ [SyncManager] Comments synced successfully")
            } catch {
                print("⚠️ [SyncManager] Comment sync failed (non-critical): \(error)")
            }

            // Sync pending list member operations (local-first offline support)
            print("🔄 [SyncManager] Syncing pending list member operations...")
            do {
                try await listMemberService.syncPendingOperations()
                print("✅ [SyncManager] List members synced successfully")
            } catch {
                print("⚠️ [SyncManager] List member sync failed (non-critical): \(error)")
            }

            // Sync pending reminder settings (local-first offline support)
            print("🔄 [SyncManager] Syncing pending reminder settings...")
            await reminderSettings.syncPendingChanges()

            // Update sync timestamps
            let syncTime = Date()
            lastSyncDate = syncTime
            lastTaskSyncDate = syncTime
            lastListSyncDate = syncTime
            lastCommentSyncDate = syncTime
            UserDefaults.standard.set(syncTime, forKey: lastSyncKey)
            UserDefaults.standard.set(syncTime, forKey: lastTaskSyncKey)
            UserDefaults.standard.set(syncTime, forKey: lastListSyncKey)
            UserDefaults.standard.set(syncTime, forKey: lastCommentSyncKey)

            print("✅ [SyncManager] Full sync completed: \(lists.count) lists, \(taskService.tasks.count) tasks")
            hasCompletedInitialSync = true
        } catch {
            print("⚠️ [SyncManager] Full sync failed (offline mode): \(error)")
            print("⚠️ [SyncManager] Error details: \(error.localizedDescription)")
            print("📱 [SyncManager] Using cached data for offline support")
            print("📊 [SyncManager] Available offline: \(listService.lists.count) lists, \(taskService.tasks.count) tasks")

            // Mark as complete even on error to not block UI forever
            hasCompletedInitialSync = true
        }
    }

    // MARK: - Background Processing Helpers

    /// Process lists in background to avoid blocking main thread during sync
    /// This handles sorting and merging which can be slow with many lists
    private static nonisolated func processListsInBackground(
        serverLists: [TaskList],
        pendingLists: [TaskList]
    ) async -> [TaskList] {
        // Run heavy processing on background thread
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Sort lists: favorites first, then alphabetical
                var sorted = serverLists.sorted { list1, list2 in
                    let fav1 = list1.isFavorite ?? false
                    let fav2 = list2.isFavorite ?? false
                    if fav1 != fav2 { return fav1 }
                    return list1.name.localizedCaseInsensitiveCompare(list2.name) == .orderedAscending
                }

                // Keep pending (temp) lists at the top
                for pendingList in pendingLists {
                    if !sorted.contains(where: { $0.id == pendingList.id }) {
                        sorted.insert(pendingList, at: 0)
                    }
                }

                continuation.resume(returning: sorted)
            }
        }
    }

    /// Process tasks in background to avoid blocking main thread during sync
    /// This handles deduplication and validation which can be slow with many tasks
    private static nonisolated func processTasksInBackground(
        serverTasks: [Task],
        currentUserId: String?
    ) async -> ([Task], SyncError?) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Deduplicate tasks using dictionary
                var taskDict: [String: Task] = [:]
                for task in serverTasks {
                    taskDict[task.id] = task
                }
                let uniqueTasks = Array(taskDict.values)

                // Validate data isolation if we have a current user
                if let userId = currentUserId {
                    let userOwnedTasks = uniqueTasks.filter { task in
                        task.creatorId == userId || task.assigneeId == userId
                    }

                    // If we got tasks but none belong to the current user, flag error
                    if !uniqueTasks.isEmpty && userOwnedTasks.isEmpty {
                        print("🚨 [SyncManager] DATA ISOLATION ALERT: Received \(uniqueTasks.count) tasks but none belong to current user \(userId)")
                        let error = SyncError.dataIsolationViolation(
                            expectedUserId: userId,
                            receivedTaskCount: uniqueTasks.count
                        )
                        continuation.resume(returning: ([], error))
                        return
                    }

                    print("✅ [SyncManager] Data validation passed: \(userOwnedTasks.count)/\(uniqueTasks.count) tasks belong to current user")
                }

                continuation.resume(returning: (uniqueTasks, nil))
            }
        }
    }

    // MARK: - Incremental Sync

    /// Perform an incremental sync (only fetch changes since last sync)
    /// Uses client-side delta detection - fetches all data but only applies newer changes
    func performIncrementalSync() async throws {
        guard let lastSync = lastSyncDate else {
            // No previous sync, do full sync (but don't throw on error)
            do {
                return try await performFullSync()
            } catch {
                print("⚠️ [SyncManager] Full sync failed (offline mode): \(error)")
                // Don't throw - allow offline mode
                return
            }
        }

        // If no data cached, force full sync even if we have a lastSyncDate
        if listService.lists.isEmpty && taskService.tasks.isEmpty {
            print("🔄 [SyncManager] No cached data - performing full sync instead")
            do {
                return try await performFullSync()
            } catch {
                print("⚠️ [SyncManager] Full sync failed (offline mode): \(error)")
                // Don't throw - allow offline mode
                return
            }
        }

        isSyncing = true
        defer { isSyncing = false }

        print("🔄 [SyncManager] Starting incremental sync (client-side delta)...")
        print("   Last sync: \(lastSync)")

        var stats = IncrementalSyncStats()

        do {
            // Fetch all lists and apply only newer changes
            let serverLists = try await apiClient.getLists()
            stats.listsChecked = serverLists.count

            for serverList in serverLists {
                if let existingIndex = listService.lists.firstIndex(where: { $0.id == serverList.id }) {
                    // Compare timestamps - only update if server is newer
                    let existingList = listService.lists[existingIndex]
                    let serverUpdated = serverList.updatedAt ?? serverList.createdAt ?? .distantPast
                    let localUpdated = existingList.updatedAt ?? existingList.createdAt ?? .distantPast

                    if serverUpdated > localUpdated {
                        listService.lists[existingIndex] = serverList
                        stats.listsUpdated += 1
                    }
                } else {
                    // New list
                    listService.lists.append(serverList)
                    stats.listsCreated += 1
                }
            }

            // Fetch all tasks and apply only newer changes
            let serverTasks = try await apiClient.getAllTasks()
            stats.tasksChecked = serverTasks.count

            for serverTask in serverTasks {
                if let existingIndex = taskService.tasks.firstIndex(where: { $0.id == serverTask.id }) {
                    // Compare timestamps - only update if server is newer
                    let existingTask = taskService.tasks[existingIndex]
                    let serverUpdated = serverTask.updatedAt ?? serverTask.createdAt ?? .distantPast
                    let localUpdated = existingTask.updatedAt ?? existingTask.createdAt ?? .distantPast

                    if serverUpdated > localUpdated {
                        taskService.tasks[existingIndex] = serverTask
                        stats.tasksUpdated += 1
                    }
                } else {
                    // New task
                    taskService.tasks.append(serverTask)
                    stats.tasksCreated += 1
                }
            }

            // Sync pending local operations
            try await taskService.syncPendingOperations()
            try await commentService.syncPendingComments()
            try await listMemberService.syncPendingOperations()

            // Update timestamps
            let syncTime = Date()
            lastSyncDate = syncTime
            lastTaskSyncDate = syncTime
            lastListSyncDate = syncTime
            UserDefaults.standard.set(syncTime, forKey: lastSyncKey)
            UserDefaults.standard.set(syncTime, forKey: lastTaskSyncKey)
            UserDefaults.standard.set(syncTime, forKey: lastListSyncKey)

            print("✅ [SyncManager] Incremental sync completed:")
            print("   Lists: \(stats.listsCreated) new, \(stats.listsUpdated) updated (checked \(stats.listsChecked))")
            print("   Tasks: \(stats.tasksCreated) new, \(stats.tasksUpdated) updated (checked \(stats.tasksChecked))")

        } catch {
            print("⚠️ [SyncManager] Incremental sync failed (offline mode): \(error)")
            // Don't throw - allow offline mode
        }
    }

    /// Perform a quick sync - only syncs pending local operations without fetching server data
    /// Useful for immediately pushing local changes without full refresh
    func performQuickSync() async throws {
        print("🔄 [SyncManager] Starting quick sync (pending operations only)...")

        do {
            try await taskService.syncPendingOperations()
            try await commentService.syncPendingComments()
            try await listMemberService.syncPendingOperations()
            print("✅ [SyncManager] Quick sync completed")
        } catch {
            print("⚠️ [SyncManager] Quick sync failed: \(error)")
            throw error
        }
    }

    // MARK: - Apply Changes

    private func applyChanges(_ syncResponse: SyncResponse) async throws {
        // Apply list changes
        for list in syncResponse.lists.created {
            if !listService.lists.contains(where: { $0.id == list.id }) {
                listService.lists.append(list)
            }
        }

        for list in syncResponse.lists.updated {
            if let index = listService.lists.firstIndex(where: { $0.id == list.id }) {
                listService.lists[index] = list
            }
        }

        // TODO: Handle deleted lists when backend supports it

        // Apply task changes
        for task in syncResponse.tasks.created {
            if !taskService.tasks.contains(where: { $0.id == task.id }) {
                taskService.tasks.append(task)
            }
        }

        for task in syncResponse.tasks.updated {
            if let index = taskService.tasks.firstIndex(where: { $0.id == task.id }) {
                taskService.tasks[index] = task
            }
        }

        // TODO: Handle deleted tasks when backend supports it

        // Re-sort tasks
        taskService.tasks.sort { task1, task2 in
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

    // MARK: - Auto Sync

    /// Start automatic background syncing
    func startAutoSync(interval: TimeInterval = 60) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                do {
                    try await self?.performIncrementalSync()
                } catch {
                    print("⚠️ [SyncManager] Auto-sync failed: \(error)")
                }
            }
        }
    }

    /// Reset sync state (useful after sign out or data corruption)
    /// Clears all sync timestamps to ensure fresh data on next login
    func resetSyncState() {
        lastSyncDate = nil
        lastTaskSyncDate = nil
        lastListSyncDate = nil
        lastCommentSyncDate = nil
        hasCompletedInitialSync = false

        // Clear all persisted sync timestamps
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        UserDefaults.standard.removeObject(forKey: lastTaskSyncKey)
        UserDefaults.standard.removeObject(forKey: lastListSyncKey)
        UserDefaults.standard.removeObject(forKey: lastCommentSyncKey)

        print("🔄 [SyncManager] Sync state fully reset (all timestamps cleared)")
    }
}

// MARK: - Sync Response Models

struct SyncResponse: Codable {
    let lists: SyncChanges<TaskList>
    let tasks: SyncChanges<Task>
    let syncTimestamp: String
    let stats: SyncStats
}

struct SyncChanges<T: Codable>: Codable {
    let created: [T]
    let updated: [T]
    let deleted: [String] // IDs of deleted items
}

struct SyncStats: Codable {
    let listsCreated: Int
    let listsUpdated: Int
    let tasksCreated: Int
    let tasksUpdated: Int
}

/// Statistics for incremental sync operations
struct IncrementalSyncStats {
    var listsChecked: Int = 0
    var listsCreated: Int = 0
    var listsUpdated: Int = 0
    var tasksChecked: Int = 0
    var tasksCreated: Int = 0
    var tasksUpdated: Int = 0
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case dataIsolationViolation(expectedUserId: String, receivedTaskCount: Int)
    case unauthorized
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .dataIsolationViolation(let expectedUserId, let receivedTaskCount):
            return "Data isolation violation: Received \(receivedTaskCount) tasks that don't belong to user \(expectedUserId). Please sign out and sign in again."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
