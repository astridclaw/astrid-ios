import Foundation
import Combine
import CoreData
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "CommentService")

@MainActor
class CommentService: ObservableObject {
    static let shared = CommentService()

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingOperationsCount: Int = 0
    @Published var failedOperationsCount: Int = 0

    private let apiClient = AstridAPIClient.shared
    private let coreDataManager = CoreDataManager.shared
    private let networkMonitor = NetworkMonitor.shared
    @Published public var cachedComments: [String: [Comment]] = [:] // taskId -> comments
    private var lastFetchTime: [String: Date] = [:] // taskId -> last fetch time
    private var networkObserver: NSObjectProtocol?

    init() {
        // Load cached comments on initialization
        _Concurrency.Task { @MainActor in
            await self.loadCachedComments()
            await self.updatePendingOperationsCount()
        }

        // Setup network observer to sync when connection is restored
        setupNetworkObserver()
    }

    deinit {
        if let observer = networkObserver {
            NotificationCenter.default.removeObserver(observer)
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
                print("🔄 [CommentService] Network restored - syncing pending comments")
                try? await self?.syncPendingComments()
            }
        }
    }

    // MARK: - Cache Management

    /// Clean up corrupted comments from old buggy data
    /// Deletes comments with: empty IDs, nil authorId (except system comments have content starting with specific patterns)
    private func cleanupCorruptedComments() async {
        do {
            let deletedCount: Int = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        // Fetch ALL comments to check for corruption
                        let fetchRequest = CDComment.fetchRequest()
                        let allComments = try context.fetch(fetchRequest)

                        var corruptedComments: [CDComment] = []

                        for comment in allComments {
                            // Delete if empty ID
                            if comment.id.isEmpty {
                                corruptedComments.append(comment)
                                continue
                            }

                            // Delete if nil authorId (legacy corrupted data)
                            // Real system comments are rare and have specific content patterns
                            if comment.authorId == nil {
                                corruptedComments.append(comment)
                                continue
                            }
                        }

                        if corruptedComments.isEmpty {
                            continuation.resume(returning: 0)
                            return
                        }

                        // Delete corrupted comments
                        for comment in corruptedComments {
                            context.delete(comment)
                        }

                        try context.save()
                        continuation.resume(returning: corruptedComments.count)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            if deletedCount > 0 {
                logger.notice("CLEANUP: Deleted \(deletedCount, privacy: .public) corrupted comments (empty IDs or nil authorId)")
            }
        } catch {
            logger.error("CLEANUP FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Load cached comments from CoreData on startup (async, non-blocking)
    /// CRITICAL: Must convert to domain models INSIDE the context to avoid faulted objects
    private func loadCachedComments() async {
        let startTime = Date()

        // CRITICAL: Wait for CoreData persistent store to be ready
        await coreDataManager.waitForStoreLoad()

        // Clean up corrupted comments (empty IDs) from old data
        await cleanupCorruptedComments()

        do {
            // Load from CoreData in background and convert to domain models INSIDE context
            let commentsByTask: [String: [Comment]] = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        let cdComments = try CDComment.fetchAll(context: context)

                        // CRITICAL: Convert to domain models INSIDE context block
                        // Otherwise managed objects are faulted and return nil for properties
                        var result: [String: [Comment]] = [:]
                        for cdComment in cdComments {
                            let comment = cdComment.toDomainModel()
                            if result[comment.taskId] == nil {
                                result[comment.taskId] = []
                            }
                            result[comment.taskId]?.append(comment)
                        }

                        // Sort comments within each task by createdAt
                        for (taskId, comments) in result {
                            result[taskId] = comments.sorted { c1, c2 in
                                guard let date1 = c1.createdAt, let date2 = c2.createdAt else {
                                    return false
                                }
                                return date1 < date2
                            }
                        }

                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            self.cachedComments = commentsByTask

            let totalComments = commentsByTask.values.reduce(0) { $0 + $1.count }
            let duration = Date().timeIntervalSince(startTime)
            if totalComments > 0 || duration > 1.0 {
                // Only log if there's something interesting (comments loaded or slow startup)
                logger.notice("Comments loaded: \(totalComments, privacy: .public) comments for \(commentsByTask.count, privacy: .public) tasks in \(String(format: "%.0f", duration * 1000), privacy: .public)ms")
            }
        } catch {
            logger.error("Failed to load cached comments: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Update the count of pending operations (for UI indicators)
    private func updatePendingOperationsCount() async {
        do {
            let pending: [CDComment] = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        let comments = try CDComment.fetchPending(context: context)
                        continuation.resume(returning: comments)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            pendingOperationsCount = pending.count
            print("📊 [CommentService] Pending operations: \(pendingOperationsCount)")
        } catch {
            print("❌ [CommentService] Failed to count pending operations: \(error)")
        }
    }

    // MARK: - Fetching

    /// Fetch comments with cache hierarchy: Memory → CoreData → Network
    /// Network results are always saved to CoreData for offline access
    func fetchComments(taskId: String, useCache: Bool = true) async throws -> [Comment] {
        logger.notice("===== fetchComments: \(taskId.prefix(8), privacy: .public) =====")

        // STEP 1: Check memory cache first (instant)
        // We check if the key exists, even if the array is empty, to avoid infinite loops
        if useCache, let cached = cachedComments[taskId] {
            logger.notice("✓ MEMORY: \(cached.count, privacy: .public) comments")
            backgroundRefreshFromNetwork(taskId: taskId)
            return cached
        }

        // STEP 2: Check CoreData (fast, persisted)
        if useCache {
            await coreDataManager.waitForStoreLoad()
            let coreDataComments = try await loadCommentsFromCoreData(taskId: taskId)
            
            // If we found comments in CoreData, return them and refresh in background
            if !coreDataComments.isEmpty {
                logger.notice("✓ COREDATA: \(coreDataComments.count, privacy: .public) comments")
                cachedComments[taskId] = coreDataComments  // populate memory cache
                backgroundRefreshFromNetwork(taskId: taskId)
                return coreDataComments
            }
        }

        // STEP 3: Fetch from network (slow, requires connection)
        logger.notice("→ NETWORK: Fetching...")
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let response: CommentsListResponse = try await apiClient.getTaskComments(taskId: taskId)
            logger.notice("✓ NETWORK: \(response.comments.count, privacy: .public) comments")

            // Update last fetch time
            lastFetchTime[taskId] = Date()

            // Save to CoreData for offline access
            try await saveCommentsToCoreData(response.comments, taskId: taskId)
            logger.notice("✓ SAVED to CoreData")

            // Update memory cache
            cachedComments[taskId] = response.comments

            // Notify views to reload comments (for pull-to-refresh updates)
            await MainActor.run {
                NotificationCenter.default.post(name: .commentDidSync, object: nil, userInfo: ["taskId": taskId])
            }

            return response.comments
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                logger.notice("✗ NETWORK: Cancelled")
                return []
            }

            logger.error("✗ NETWORK: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Load comments from CoreData for a specific task
    /// CRITICAL: Must convert to domain models INSIDE the context to avoid faulted objects
    private func loadCommentsFromCoreData(taskId: String) async throws -> [Comment] {
        let comments: [Comment] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let fetchRequest = CDComment.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "taskId == %@", taskId)
                    fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                    let cdComments = try context.fetch(fetchRequest)

                    // CRITICAL: Convert to domain models INSIDE context block
                    // Otherwise managed objects are faulted and return nil for properties
                    let domainComments = cdComments.map { $0.toDomainModel() }
                    continuation.resume(returning: domainComments)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return comments
    }

    /// Background refresh from network (fire-and-forget)
    private func backgroundRefreshFromNetwork(taskId: String) {
        // Throttle background refreshes to once every 30 seconds per task
        if let lastFetch = lastFetchTime[taskId], Date().timeIntervalSince(lastFetch) < 30 {
            return
        }
        
        // Update last fetch time immediately to prevent concurrent background refreshes
        lastFetchTime[taskId] = Date()

        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let response: CommentsListResponse = try await self.apiClient.getTaskComments(taskId: taskId)
                try await self.saveCommentsToCoreData(response.comments, taskId: taskId)
                let count = response.comments.count
                await MainActor.run {
                    self.cachedComments[taskId] = response.comments
                    // Log on MainActor to satisfy Swift 6 isolation requirements
                    logger.notice("↻ BACKGROUND: Updated \(count, privacy: .public) comments")
                    // Notify views to reload comments (for background refresh updates)
                    NotificationCenter.default.post(name: .commentDidSync, object: nil, userInfo: ["taskId": taskId])
                }
            } catch {
                // Silent fail - already returned cached data
            }
        }
    }

    /// Create a new comment (local-first with optimistic update)
    func createComment(taskId: String, content: String, type: Comment.CommentType = .TEXT, fileId: String? = nil, parentCommentId: String? = nil, authorId: String? = nil) async throws -> Comment {
        print("⚡️ [CommentService] Creating comment (optimistic) for task: \(taskId)")
        print("📝 [CommentService] Content: \(content.prefix(50))...")

        // 1. Generate temp ID for optimistic update
        let tempId = "temp_\(UUID().uuidString)"

        // 2. Create optimistic comment object
        let optimisticComment = Comment(
            id: tempId,
            content: content,
            type: type,
            authorId: authorId,
            author: nil,
            taskId: taskId,
            createdAt: Date(),
            updatedAt: Date(),
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: parentCommentId,
            replies: nil,
            secureFiles: nil
        )

        // 3. Save to Core Data with pending status (non-blocking)
        let savedFileId = fileId  // Capture for closure
        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try await self.coreDataManager.saveInBackground { context in
                    let cdComment = CDComment(context: context)
                    cdComment.id = tempId
                    cdComment.content = content
                    cdComment.type = type.rawValue
                    cdComment.authorId = authorId
                    cdComment.taskId = taskId
                    cdComment.createdAt = Date()
                    cdComment.updatedAt = Date()
                    cdComment.syncStatus = "pending"
                    cdComment.pendingOperation = "create"
                    cdComment.syncAttempts = 0
                    cdComment.pendingFileId = savedFileId  // Store fileId for sync
                }

                // Update pending count
                await self.updatePendingOperationsCount()
                print("💾 [CommentService] Saved pending comment to Core Data: \(tempId)")
            } catch {
                print("⚠️ [CommentService] Failed to save pending comment: \(error)")
            }
        }

        // 4. Update in-memory cache immediately
        if cachedComments[taskId] == nil {
            cachedComments[taskId] = []
        }
        cachedComments[taskId]?.append(optimisticComment)

        // 5. Trigger background sync (fire-and-forget)
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                try? await self?.syncPendingComments()
            }
        } else {
            print("📵 [CommentService] Offline - comment will sync when connection restored")
        }

        // 6. Return optimistic comment immediately
        print("✅ [CommentService] Returning optimistic comment (pending sync)")
        return optimisticComment
    }

    /// Update a comment (local-first with optimistic update)
    func updateComment(id: String, content: String) async throws -> Comment {
        print("✏️ [CommentService] Updating comment (optimistic): \(id)")

        // 1. Create updated comment object
        let updatedComment = Comment(
            id: id,
            content: content,
            type: .TEXT, // Preserve existing type
            authorId: nil,
            author: nil,
            taskId: "", // Will be populated from cache
            createdAt: nil,
            updatedAt: Date(),
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: nil,
            replies: nil,
            secureFiles: nil
        )

        // 2. Update in-memory cache immediately
        for (taskId, comments) in cachedComments {
            if let index = comments.firstIndex(where: { $0.id == id }) {
                var updated = comments[index]
                updated.content = content
                updated.updatedAt = Date()
                cachedComments[taskId]?[index] = updated
                break
            }
        }

        // 3. Save to Core Data with pending status (non-blocking)
        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try await self.coreDataManager.saveInBackground { context in
                    guard let cdComment = try CDComment.fetchById(id, context: context) else {
                        print("⚠️ [CommentService] Comment not found in Core Data: \(id)")
                        return
                    }

                    cdComment.pendingContent = content
                    cdComment.syncStatus = "pending_update"
                    cdComment.pendingOperation = "update"
                    cdComment.updatedAt = Date()
                    cdComment.syncAttempts = 0
                }

                // Update pending count
                await self.updatePendingOperationsCount()
                print("💾 [CommentService] Saved pending update to Core Data: \(id)")
            } catch {
                print("⚠️ [CommentService] Failed to save pending update: \(error)")
            }
        }

        // 4. Trigger background sync (fire-and-forget)
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                try? await self?.syncPendingComments()
            }
        } else {
            print("📵 [CommentService] Offline - update will sync when connection restored")
        }

        // 5. Return updated comment immediately
        print("✅ [CommentService] Returning updated comment (pending sync)")
        return updatedComment
    }

    /// Delete a comment (local-first with optimistic update)
    func deleteComment(id: String) async throws {
        print("🗑️ [CommentService] Deleting comment (optimistic): \(id)")

        // 1. Remove from in-memory cache immediately (optimistic)
        for (taskId, comments) in cachedComments {
            if let index = comments.firstIndex(where: { $0.id == id }) {
                cachedComments[taskId]?.remove(at: index)
                print("✅ [CommentService] Removed from cache (optimistic)")
                break
            }
        }

        // 2. Mark as pending delete in Core Data (non-blocking)
        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try await self.coreDataManager.saveInBackground { context in
                    guard let cdComment = try CDComment.fetchById(id, context: context) else {
                        print("⚠️ [CommentService] Comment not found in Core Data: \(id)")
                        return
                    }

                    cdComment.syncStatus = "pending_delete"
                    cdComment.pendingOperation = "delete"
                    cdComment.syncAttempts = 0
                }

                // Update pending count
                await self.updatePendingOperationsCount()
                print("💾 [CommentService] Marked comment for deletion in Core Data: \(id)")
            } catch {
                print("⚠️ [CommentService] Failed to mark for deletion: \(error)")
            }
        }

        // 3. Trigger background sync (fire-and-forget)
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                try? await self?.syncPendingComments()
            }
        } else {
            print("📵 [CommentService] Offline - deletion will sync when connection restored")
        }

        print("✅ [CommentService] Comment deleted (pending sync)")
    }

    // MARK: - Background Sync

    /// Data extracted from CDComment for sync operations (to avoid CoreData context faulting)
    private struct PendingCommentData {
        let id: String
        let taskId: String
        let content: String
        let type: String
        let operation: String
        let pendingContent: String?
        let pendingFileId: String?  // For attachment uploads
        let createdAt: Date?  // Client timestamp for correct ordering
    }

    /// Sync all pending comment operations (create, update, delete) with the server
    func syncPendingComments() async throws {
        guard networkMonitor.isConnected else {
            print("📵 [CommentService] Cannot sync - no network connection")
            return
        }

        print("🔄 [CommentService] Starting pending comments sync...")

        // Fetch all pending comments from Core Data - extract data INSIDE context to avoid faulting
        let pendingData: [PendingCommentData] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let comments = try CDComment.fetchPending(context: context)

                    // CRITICAL: Extract all data INSIDE context before objects become faulted
                    let extracted = comments.map { cdComment in
                        PendingCommentData(
                            id: cdComment.id,
                            taskId: cdComment.taskId,
                            content: cdComment.content,
                            type: cdComment.type,
                            operation: cdComment.pendingOperation ?? "unknown",
                            pendingContent: cdComment.pendingContent,
                            pendingFileId: cdComment.pendingFileId,
                            createdAt: cdComment.createdAt
                        )
                    }
                    continuation.resume(returning: extracted)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        print("📊 [CommentService] Found \(pendingData.count) pending operations to sync")

        if pendingData.isEmpty {
            print("✅ [CommentService] No pending operations to sync")
            return
        }

        // Process each pending operation using extracted data
        for data in pendingData {
            print("⚡️ [CommentService] Processing pending \(data.operation) for comment: \(data.id)")

            do {
                switch data.operation {
                case "create":
                    try await syncPendingCreate(data)

                case "update":
                    try await syncPendingUpdate(data)

                case "delete":
                    try await syncPendingDelete(data)

                default:
                    print("⚠️ [CommentService] Unknown operation: \(data.operation)")
                    try await markAsFailed(id: data.id, error: "Unknown operation type")
                }
            } catch {
                print("❌ [CommentService] Failed to sync \(data.operation): \(error.localizedDescription)")
                try await markAsFailed(id: data.id, error: error.localizedDescription)
            }
        }

        // Update pending count after sync
        await updatePendingOperationsCount()
        print("✅ [CommentService] Sync completed")

        // Notify views to reload comments (updates UI after sync replaces temp IDs)
        NotificationCenter.default.post(name: .commentDidSync, object: nil)
    }

    /// Sync a pending create operation
    private func syncPendingCreate(_ data: PendingCommentData) async throws {
        print("⚡️ [CommentService] Syncing pending create: \(data.id)")
        if let fileId = data.pendingFileId {
            print("📎 [CommentService] Attaching file: \(fileId)")
        }

        // Call API to create comment (pass client createdAt for correct ordering)
        let response = try await apiClient.createComment(
            taskId: data.taskId,
            content: data.content,
            type: Comment.CommentType(rawValue: data.type) ?? .TEXT,
            fileId: data.pendingFileId,
            parentCommentId: nil,
            createdAt: data.createdAt
        )

        print("✅ [CommentService] Server created comment with ID: \(response.comment.id)")

        // Update Core Data with server ID and mark as synced
        let oldId = data.id
        try await coreDataManager.saveInBackground { context in
            guard let comment = try CDComment.fetchById(oldId, context: context) else {
                print("⚠️ [CommentService] Could not find comment in Core Data: \(oldId)")
                return
            }

            // Update with server response
            comment.id = response.comment.id // Replace temp ID with real ID
            comment.syncStatus = "synced"
            comment.lastSyncedAt = Date()
            comment.pendingOperation = nil
            comment.pendingContent = nil
            comment.syncAttempts = 0
            comment.syncError = nil
        }

        // Update in-memory cache: replace temp comment with synced one
        let taskId = data.taskId
        if var taskComments = cachedComments[taskId] {
            if let index = taskComments.firstIndex(where: { $0.id == oldId }) {
                taskComments[index] = response.comment
                cachedComments[taskId] = taskComments
            }
        }

        print("✅ [CommentService] Marked comment as synced: \(response.comment.id)")
    }

    /// Sync a pending update operation
    private func syncPendingUpdate(_ data: PendingCommentData) async throws {
        print("⚡️ [CommentService] Syncing pending update: \(data.id)")

        guard let updatedContent = data.pendingContent else {
            print("⚠️ [CommentService] No pending content for update")
            return
        }

        // Call API to update comment
        let response = try await apiClient.updateComment(
            commentId: data.id,
            content: updatedContent
        )

        print("✅ [CommentService] Server confirmed update for comment: \(response.comment.id)")

        // Mark as synced in Core Data
        let commentId = data.id
        try await coreDataManager.saveInBackground { context in
            guard let comment = try CDComment.fetchById(commentId, context: context) else {
                print("⚠️ [CommentService] Could not find comment in Core Data: \(commentId)")
                return
            }

            comment.content = updatedContent
            comment.syncStatus = "synced"
            comment.lastSyncedAt = Date()
            comment.pendingOperation = nil
            comment.pendingContent = nil
            comment.syncAttempts = 0
            comment.syncError = nil
        }

        print("✅ [CommentService] Marked comment as synced: \(response.comment.id)")
    }

    /// Sync a pending delete operation
    private func syncPendingDelete(_ data: PendingCommentData) async throws {
        print("⚡️ [CommentService] Syncing pending delete: \(data.id)")

        // Call API to delete comment
        let _ = try await apiClient.deleteComment(commentId: data.id)

        print("✅ [CommentService] Server confirmed delete for comment: \(data.id)")

        // Remove from Core Data
        let commentId = data.id
        try await coreDataManager.saveInBackground { context in
            guard let comment = try CDComment.fetchById(commentId, context: context) else {
                print("⚠️ [CommentService] Comment already deleted from Core Data: \(commentId)")
                return
            }

            context.delete(comment)
        }

        print("✅ [CommentService] Removed comment from Core Data: \(data.id)")
    }

    /// Mark a comment as failed after sync error
    private func markAsFailed(id: String, error: String) async throws {
        print("⚠️ [CommentService] Marking comment as failed: \(id)")

        try await coreDataManager.saveInBackground { context in
            guard let comment = try CDComment.fetchById(id, context: context) else {
                print("⚠️ [CommentService] Could not find comment in Core Data: \(id)")
                return
            }

            comment.syncStatus = "failed"
            comment.syncAttempts += 1
            comment.syncError = error

            // Give up after 3 attempts
            if comment.syncAttempts >= 3 {
                print("🛑 [CommentService] Comment failed after 3 attempts, giving up: \(id)")
            }
        }
    }
}

// MARK: - Response Models

struct CommentsListResponse: Codable {
    let comments: [Comment]
    let meta: MetaInfo
}

struct CommentResponse: Codable {
    let comment: Comment
    let meta: MetaInfo
}

struct DeleteResponse: Codable {
    let success: Bool
    let message: String
    let meta: MetaInfo
}

struct MetaInfo: Codable {
    let apiVersion: String?
    let authSource: String?
}

// MARK: - CoreData Persistence (Extension)

extension CommentService {
    /// Save multiple comments to CoreData for a specific task
    private func saveCommentsToCoreData(_ comments: [Comment], taskId: String) async throws {
        logger.notice("💾 Starting CoreData save for task \(taskId.prefix(8), privacy: .public)")
        logger.notice("💾 Comments to save: \(comments.count, privacy: .public)")

        // CRITICAL: Wait for CoreData persistent store to be ready
        await coreDataManager.waitForStoreLoad()

        let startTime = Date()

        try await coreDataManager.saveInBackground { context in
            // Fetch all existing comments for this task in ONE batch query
            let commentIds = comments.map { $0.id }

            let fetchRequest = CDComment.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", commentIds)
            let existingComments = try context.fetch(fetchRequest)

            // Create dictionary for O(1) lookup
            var existingCommentsDict = [String: CDComment]()
            for cdComment in existingComments {
                existingCommentsDict[cdComment.id] = cdComment
            }

            let newCommentsCount = comments.count - existingComments.count
            logger.notice("💾 Will update \(existingComments.count, privacy: .public) existing, create \(newCommentsCount, privacy: .public) new")

            // Update or create comments
            var updatedCount = 0
            var createdCount = 0

            for comment in comments {
                let isExisting = existingCommentsDict[comment.id] != nil
                let cdComment = existingCommentsDict[comment.id] ?? CDComment(context: context)

                cdComment.id = comment.id
                cdComment.update(from: comment)
                // CRITICAL: Explicitly set taskId from parameter (don't rely on comment.taskId)
                cdComment.taskId = taskId

                cdComment.syncStatus = "synced"
                cdComment.lastSyncedAt = Date()

                if isExisting {
                    updatedCount += 1
                } else {
                    createdCount += 1
                }
            }

            logger.notice("💾 CoreData: updated \(updatedCount, privacy: .public), created \(createdCount, privacy: .public) comments")
        }

        let duration = Date().timeIntervalSince(startTime)
        logger.notice("✅ CoreData save completed in \(String(format: "%.0f", duration * 1000), privacy: .public)ms for \(comments.count, privacy: .public) comments")
    }

    /// Save single comment to CoreData
    private func saveCommentToCoreData(_ comment: Comment, syncStatus: String = "synced") async throws {
        try await coreDataManager.saveInBackground { context in
            let cdComment = try CDComment.fetchById(comment.id, context: context) ?? CDComment(context: context)
            cdComment.id = comment.id
            cdComment.update(from: comment)
            cdComment.syncStatus = syncStatus
            if syncStatus == "synced" {
                cdComment.lastSyncedAt = Date()
            }
        }
    }

    /// Retry all failed operations
    func retryFailedOperations() async {
        print("🔄 [CommentService] Retrying failed operations...")

        do {
            try await coreDataManager.saveInBackground { context in
                let request = CDComment.fetchRequest()
                request.predicate = NSPredicate(format: "syncStatus == %@", "failed")
                let failedComments = try context.fetch(request)
                for comment in failedComments {
                    comment.syncAttempts = 0
                    comment.syncStatus = "pending"
                    comment.syncError = nil
                }
                print("📊 [CommentService] Reset \(failedComments.count) failed comments to pending")
            }

            // Trigger sync
            try await syncPendingComments()
        } catch {
            print("❌ [CommentService] Failed to retry operations: \(error)")
        }
    }
}
