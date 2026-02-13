import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "CommentSection")

struct AttachedFileInfo {
    let fileId: String
    let fileName: String
    let fileSize: Int
    let mimeType: String
    let imageData: Data?  // For thumbnail preview (images only)

    var isImage: Bool {
        mimeType.lowercased().hasPrefix("image/")
    }
}

/// Enhanced Comment Section with Markdown and SSE support
struct CommentSectionViewEnhanced: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    let taskId: String
    @StateObject private var commentService = CommentService.shared
    @StateObject private var attachmentService = AttachmentService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var comments: [Comment] = []
    @State private var newCommentText = ""
    @State private var isSubmitting = false
    @State private var replyingTo: Comment?
    // Always use markdown - no toggle needed
    private let useMarkdown = true
    @FocusState private var isTextFieldFocused: Bool
    @State private var showSystemComments = false

    // Attachment state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingVideoPicker = false
    @State private var showingDocumentPicker = false
    @State private var attachedFile: AttachedFileInfo?
    @State private var isUploadingFile = false
    @State private var uploadError: String?

    // Mention state - cached to avoid expensive traversal on every keystroke
    @State private var mentionSearch: String?
    @State private var cachedMentionableUsers: [User] = []
    @State private var filteredMentionResults: [User] = []
    @State private var mentionSearchTask: _Concurrency.Task<Void, Never>?

    /// Build the mentionable users list from task and list data
    /// Called once on appear and when task/list data changes
    private func updateMentionableUsers() {
        guard let task = TaskService.shared.tasks.first(where: { $0.id == taskId }) else {
            cachedMentionableUsers = []
            return
        }

        var users: [String: User] = [:]

        if let creator = task.creator {
            users[creator.id] = creator
        }

        if let assignee = task.assignee {
            users[assignee.id] = assignee
        }

        for list in task.lists ?? [] {
            if let fullList = ListService.shared.lists.first(where: { $0.id == list.id }) {
                if let owner = fullList.owner {
                    users[owner.id] = owner
                }
                for member in fullList.members ?? [] {
                    users[member.id] = member
                }
                for admin in fullList.admins ?? [] {
                    users[admin.id] = admin
                }
                for lm in fullList.listMembers ?? [] {
                    if let user = lm.user {
                        users[user.id] = user
                    }
                }
            }
        }

        let currentUserId = AuthManager.shared.userId
        cachedMentionableUsers = Array(users.values).filter { $0.id != currentUserId }
    }

    /// Filter mentionable users with debounce to prevent main thread blocking
    private func filterMentionableUsers(search: String?) {
        // Cancel any pending search
        mentionSearchTask?.cancel()

        guard let search = search, !search.isEmpty else {
            filteredMentionResults = []
            return
        }

        // Debounce: wait 100ms before filtering to batch rapid keystrokes
        mentionSearchTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)  // 100ms

            guard !_Concurrency.Task.isCancelled else { return }

            let lowercasedSearch = search.lowercased()
            let results = cachedMentionableUsers.filter {
                $0.displayName.lowercased().contains(lowercasedSearch) ||
                ($0.email?.lowercased().contains(lowercasedSearch) ?? false)
            }

            await MainActor.run {
                guard !_Concurrency.Task.isCancelled else { return }
                filteredMentionResults = results
            }
        }
    }

    // SSE unsubscribe closures
    @State private var unsubscribeCommentAdded: (@Sendable () -> Void)?
    @State private var unsubscribeCommentUpdated: (@Sendable () -> Void)?
    @State private var unsubscribeCommentDeleted: (@Sendable () -> Void)?

    // Computed properties for filtering comments
    private var userComments: [Comment] {
        comments.filter { $0.authorId != nil }
    }

    private var systemComments: [Comment] {
        comments.filter { $0.authorId == nil }
    }

    private var displayedComments: [Comment] {
        // When offline, show all comments regardless of authorId
        // (cached comments may not have authorId populated due to caching bug)
        if !networkMonitor.isConnected {
            return comments
        }
        return showSystemComments ? comments : userComments
    }

    private var displayedCommentCount: Int {
        // When offline, show all comments
        if !networkMonitor.isConnected {
            return comments.count
        }
        return showSystemComments ? comments.count : userComments.count
    }

    private var allTaskFiles: [SecureFile] {
        var files: [SecureFile] = []
        
        // 1. Add direct task attachments
        if let task = TaskService.shared.tasks.first(where: { $0.id == taskId }) {
            if let taskFiles = task.secureFiles {
                files.append(contentsOf: taskFiles)
            }
            
            // 2. Add legacy attachments
            if let legacyAttachments = task.attachments {
                for att in legacyAttachments {
                    files.append(SecureFile(
                        id: att.id,
                        name: att.name,
                        size: att.size,
                        mimeType: att.type
                    ))
                }
            }
        }
        
        // 3. Add files from all comments (using CommentService cache)
        if let taskComments = CommentService.shared.cachedComments[taskId] {
            for comment in taskComments {
                if let commentFiles = comment.secureFiles {
                    files.append(contentsOf: commentFiles)
                }
            }
        }
        
        // 4. Remove duplicates by ID
        var uniqueFiles: [SecureFile] = []
        var seenIds = Set<String>()
        for file in files {
            if !seenIds.contains(file.id) {
                uniqueFiles.append(file)
                seenIds.insert(file.id)
            }
        }
        
        return uniqueFiles
    }

    private func insertMention(_ user: User) {
        guard let lastAtRange = newCommentText.range(of: "@", options: .backwards) else { return }
        
        let mentionText = "@[\(user.displayName)](\(user.id)) "
        newCommentText = newCommentText.replacingCharacters(in: lastAtRange.lowerBound..<newCommentText.endIndex, with: mentionText)
        mentionSearch = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            // Header (show even when offline)
            HStack {
                Text(String(format: NSLocalizedString("comments.count", comment: "Comments count"), displayedCommentCount))
                    .font(Theme.Typography.headline())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                if !systemComments.isEmpty {
                    Button(action: {
                        showSystemComments.toggle()
                    }) {
                        Text(showSystemComments ? "Hide system" : "Show system")
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }

                Spacer()

                // Show offline indicator if not connected
                if !networkMonitor.isConnected {
                    HStack(spacing: Theme.spacing4) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12))
                        Text("Offline")
                            .font(Theme.Typography.caption2())
                    }
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }

                if commentService.isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(0.8)
                }
            }

            // Comments list
            if displayedComments.isEmpty {
                Text(NSLocalizedString("comments.empty", comment: "No comments yet. Be the first to comment!"))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    .padding(.vertical, Theme.spacing8)
            } else {
                // Use comment.id directly - must ensure all comments have valid IDs
                ForEach(displayedComments, id: \.stableId) { comment in
                    CommentRowViewEnhanced(
                        comment: comment,
                        allTaskFiles: allTaskFiles,
                        colorScheme: colorScheme,
                        useMarkdown: useMarkdown,
                        isOffline: !networkMonitor.isConnected,
                        onReply: {
                            replyingTo = comment
                            isTextFieldFocused = true
                        },
                        onDelete: {
                            // Remove comment from UI immediately
                            comments.removeAll { $0.id == comment.id }
                        }
                    )
                }
            }

            // New comment input (offline sync supported via optimistic updates)
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                if let replyingTo = replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.author?.displayName ?? "Unknown")")
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                        Spacer()

                        Button("Cancel") {
                            self.replyingTo = nil
                        }
                        .font(Theme.Typography.caption1())
                        .foregroundColor(Theme.accent)
                    }
                    .padding(.horizontal, Theme.spacing12)
                    .padding(.vertical, Theme.spacing8)
                    .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }

                // File attachment preview - thumbnail for images, compact card for others
                if let file = attachedFile {
                    HStack(alignment: .bottom, spacing: Theme.spacing8) {
                        // Thumbnail or file icon
                        ZStack(alignment: .topTrailing) {
                            if file.isImage, let imageData = file.imageData, let uiImage = UIImage(data: imageData) {
                                // Image thumbnail
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                            } else {
                                // File icon for non-images
                                ZStack {
                                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                        .fill(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                                        .frame(width: 64, height: 64)

                                    VStack(spacing: 4) {
                                        Image(systemName: fileIcon(for: file.mimeType))
                                            .font(.system(size: 24))
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                                        Text(file.fileName.components(separatedBy: ".").last?.uppercased() ?? "FILE")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    }
                                }
                            }

                            // X button overlay
                            Button {
                                // Cancel pending upload if still in progress
                                if file.fileId.hasPrefix("temp_") {
                                    attachmentService.cancelUpload(tempFileId: file.fileId)
                                }
                                attachedFile = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, Color.black.opacity(0.6))
                                    .background(Circle().fill(Color.black.opacity(0.3)))
                            }
                            .offset(x: 6, y: -6)
                        }

                        Spacer()
                    }
                }

                // Mention autocomplete list - uses pre-filtered results with debounce
                if mentionSearch != nil && !filteredMentionResults.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredMentionResults) { user in
                            Button {
                                insertMention(user)
                            } label: {
                                HStack {
                                    // Avatar
                                    CachedAsyncImage(url: user.image.flatMap { URL(string: $0) }) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ZStack {
                                            Circle()
                                                .fill(Theme.accent)
                                            Text(user.initials)
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(Theme.accentText)
                                        }
                                    }
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())

                                    Text(user.displayName)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Spacer()
                                }
                                .padding(Theme.spacing8)
                            }
                            Divider()
                        }
                    }
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .cornerRadius(Theme.radiusSmall)
                    .shadow(radius: 2)
                    .padding(.horizontal, Theme.spacing4)
                }

                HStack(alignment: .bottom, spacing: Theme.spacing8) {
                    // Expandable comment input (like QuickAddTaskView)
                    ZStack(alignment: .topLeading) {
                        // Hidden sizing text - determines the height of the container
                        Text(newCommentText.isEmpty ? " " : newCommentText)
                            .font(Theme.Typography.body())
                            .foregroundColor(.clear)
                            .padding(Theme.spacing12)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Placeholder text
                        if newCommentText.isEmpty {
                            Text("Add a comment...")
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                .padding(Theme.spacing12)
                                .allowsHitTesting(false)
                        }

                        // Actual TextEditor
                        TextEditor(text: $newCommentText)
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, Theme.spacing8)
                            .padding(.vertical, Theme.spacing4)
                            .focused($isTextFieldFocused)
                            .onChange(of: newCommentText) { _, newValue in
                                // Detect @ mention
                                if let lastAtRange = newValue.range(of: "@", options: .backwards) {
                                    let substring = newValue[lastAtRange.upperBound...]
                                    if !substring.contains(" ") {
                                        let search = String(substring)
                                        mentionSearch = search
                                        filterMentionableUsers(search: search)
                                        return
                                    }
                                }
                                mentionSearch = nil
                                filteredMentionResults = []
                            }
                    }
                    .frame(minHeight: 44, maxHeight: 200)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))

                    // Attachment menu button with paperclip icon
                    Menu {
                        // Photo picker option
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            Label(NSLocalizedString("attachments.choose_photo", comment: "Choose Photo"), systemImage: "photo")
                        }

                        // Video picker option
                        Button {
                            showingVideoPicker = true
                        } label: {
                            Label(NSLocalizedString("attachments.choose_video", comment: "Choose Video"), systemImage: "video")
                        }

                        // Document picker option
                        Button {
                            showingDocumentPicker = true
                        } label: {
                            Label(NSLocalizedString("attachments.choose_document", comment: "Choose Document"), systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: isUploadingFile ? "arrow.up.circle" : "paperclip")
                            .font(.system(size: 16))
                            .foregroundColor(isUploadingFile ? .gray : Theme.accent)
                            .padding(10)
                            .background(themeMode == "ocean" ? Color.white : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploadingFile || isSubmitting)

                    Button {
                        _Concurrency.Task { await submitComment() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .tint(Theme.accent)
                                .padding(10)
                                .background(themeMode == "ocean" ? Color.white : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Theme.accent)
                                .padding(10)
                                .background(themeMode == "ocean" ? Color.white : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled((newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedFile == nil) || isSubmitting)
                }
            }
        }
        .task {
            // Cache mentionable users on first load
            updateMentionableUsers()
            await loadComments()
            await subscribeToSSE()
        }
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            if newValue && !oldValue {
                // Connection restored - reload comments
                _Concurrency.Task {
                    await loadComments()
                    await subscribeToSSE()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commentDidSync)) { notification in
            // Only reload if notification is for this task (or no taskId specified for backwards compat)
            if let notificationTaskId = notification.userInfo?["taskId"] as? String {
                guard notificationTaskId == taskId else { return }
            }
            // Reload comments after sync/refresh completes
            _Concurrency.Task {
                await loadComments()
            }
        }
        .onDisappear {
            unsubscribeFromSSE()
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            guard let photoItem = newValue else { return }
            _Concurrency.Task {
                await uploadPhotoItem(photoItem)
            }
        }
        .onChange(of: selectedVideoItem) { oldValue, newValue in
            guard let videoItem = newValue else { return }
            _Concurrency.Task {
                await uploadVideoItem(videoItem)
            }
        }
        .fileImporter(
            isPresented: $showingDocumentPicker,
            allowedContentTypes: [.pdf, .plainText, .zip, .image, .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi, UTType(filenameExtension: "doc")!, UTType(filenameExtension: "docx")!, UTType(filenameExtension: "mkv")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                _Concurrency.Task {
                    await uploadDocument(url)
                }
            case .failure(let error):
                print("❌ Document picker error: \(error)")
                uploadError = "Failed to select document: \(error.localizedDescription)"
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .photosPicker(
            isPresented: $showingVideoPicker,
            selection: $selectedVideoItem,
            matching: .videos,
            photoLibrary: .shared()
        )
        .alert(NSLocalizedString("comments.upload_error", comment: "Upload Error"), isPresented: .init(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        )) {
            Button("OK", role: .cancel) {
                uploadError = nil
            }
        } message: {
            if let error = uploadError {
                Text(error)
            }
        }
    }

    private func loadComments() async {
        logger.notice("loadComments: taskId=\(self.taskId.prefix(8), privacy: .public), current=\(self.comments.count, privacy: .public)")

        // Keep track of our local comments (for merging)
        // Use uniquingKeysWith to safely handle duplicate IDs (can occur with corrupted data)
        let localComments = Dictionary(comments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pendingComments = comments.filter { $0.id.hasPrefix("temp_") }

        do {
            let fetchedComments = try await commentService.fetchComments(taskId: taskId, useCache: true)
            logger.notice("✅ Fetched \(fetchedComments.count, privacy: .public) comments")

            // Build merged list: use fetched comments, but prefer local data for existing ones
            var mergedComments: [Comment] = []

            for var fetched in fetchedComments {

                // If we have local version with better data, use it
                if let local = localComments[fetched.id] {
                    // Keep local secureFiles if server didn't return them
                    if (fetched.secureFiles == nil || fetched.secureFiles?.isEmpty == true),
                       let localFiles = local.secureFiles, !localFiles.isEmpty {
                        fetched.secureFiles = localFiles
                    }
                    // Keep local author if server didn't return it
                    if fetched.author == nil, let localAuthor = local.author {
                        fetched.author = localAuthor
                        fetched.authorId = localAuthor.id
                    }
                }
                mergedComments.append(fetched)
            }

            // Add pending comments that haven't synced yet
            for pending in pendingComments {
                // Check if it synced (same content, similar time)
                let synced = fetchedComments.contains {
                    $0.content == pending.content &&
                    abs(($0.createdAt ?? Date()).timeIntervalSince(pending.createdAt ?? Date())) < 60
                }
                if !synced {
                    mergedComments.append(pending)
                }
            }

            // Sort by createdAt to maintain correct order (pending comments may have earlier timestamps)
            mergedComments.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }

            comments = mergedComments
            logger.notice("✅ Final: \(self.comments.count, privacy: .public) comments")
        } catch {
            logger.error("❌ loadComments failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func subscribeToSSE() async {
        // Skip SSE subscription when offline
        guard networkMonitor.isConnected else {
            print("📵 [CommentSection] Skipping SSE subscription - device is offline")
            return
        }

        print("📡 [CommentSection] Subscribing to SSE events for task \(taskId)")

        // Subscribe to comment events and store unsubscribe closures
        unsubscribeCommentAdded = await SSEClient.shared.onCommentAdded { [taskId] comment, relatedTaskId in
            guard relatedTaskId == taskId else { return }
            print("✅ [CommentSection] SSE comment_added: \(comment.id)")
            _Concurrency.Task { @MainActor in
                // Skip if we already have this comment
                if comments.contains(where: { $0.id == comment.id }) {
                    print("⚠️ [CommentSection] Skipping duplicate: \(comment.id)")
                    return
                }

                // Check if this is a synced version of a temp comment (match by content)
                if let index = comments.firstIndex(where: { $0.id.hasPrefix("temp_") && $0.content == comment.content }) {
                    // Just update the ID - keep our local data (author, secureFiles, etc.)
                    comments[index].id = comment.id
                    print("✅ [CommentSection] Updated temp → real ID: \(comment.id)")
                } else {
                    // Truly new comment from another user/device
                    comments.append(comment)
                    print("✅ [CommentSection] Added new comment: \(comment.id)")
                }
            }
        }

        unsubscribeCommentUpdated = await SSEClient.shared.onCommentUpdated { [taskId] comment, relatedTaskId in
            guard relatedTaskId == taskId else { return }
            print("✅ [CommentSection] SSE comment_updated: \(comment.id)")
            _Concurrency.Task { @MainActor in
                if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                    // Only update content - keep our local secureFiles, author, etc.
                    comments[index].content = comment.content
                    comments[index].updatedAt = comment.updatedAt
                    print("✅ [CommentSection] Updated content for: \(comment.id)")
                }
            }
        }

        unsubscribeCommentDeleted = await SSEClient.shared.onCommentDeleted { [taskId] commentId, relatedTaskId in
            guard relatedTaskId == taskId else {
                print("🔕 [CommentSection] Ignoring comment_deleted for different task (got \(relatedTaskId), want \(taskId))")
                return
            }
            print("✅ [CommentSection] Received comment_deleted for task \(taskId)")
            _Concurrency.Task { @MainActor in
                let beforeCount = comments.count
                comments.removeAll { $0.id == commentId }
                let afterCount = comments.count
                if beforeCount > afterCount {
                    print("✅ [CommentSection] Removed comment from UI: \(commentId)")
                } else {
                    print("⚠️ [CommentSection] Comment not found for deletion: \(commentId)")
                }
            }
        }

        print("✅ [CommentSection] SSE subscriptions registered")
    }

    private func unsubscribeFromSSE() {
        print("📡 [CommentSection] Unsubscribing from SSE events for task \(taskId)")

        unsubscribeCommentAdded?()
        unsubscribeCommentUpdated?()
        unsubscribeCommentDeleted?()

        unsubscribeCommentAdded = nil
        unsubscribeCommentUpdated = nil
        unsubscribeCommentDeleted = nil

        print("✅ [CommentSection] SSE subscriptions cleaned up")
    }

    private func submitComment() async {
        let trimmedText = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || attachedFile != nil else { return }

        // Determine comment type based on attachment or markdown
        let commentType: Comment.CommentType
        if attachedFile != nil {
            commentType = .ATTACHMENT
        } else if useMarkdown {
            commentType = .MARKDOWN
        } else {
            commentType = .TEXT
        }

        // Prepare content - attachment-only comments have empty text (attachment shows as thumbnail)
        let commentContent = trimmedText

        // OPTIMISTIC UPDATE: Create and show comment immediately
        let tempId = "temp_\(UUID().uuidString)"

        // Build author from all available sources - currentUser, UserDefaults, or fallback
        let userId = AuthManager.shared.userId ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userId) ?? "me"
        let userName = AuthManager.shared.currentUser?.name
            ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userName)
        let userEmail = AuthManager.shared.currentUser?.email
            ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userEmail)
        let userImage = AuthManager.shared.currentUser?.image
            ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userImage)

        // Use "Me" as fallback name if we have no user info at all
        let displayName = userName ?? userEmail ?? "Me"

        let author = User(
            id: userId,
            email: userEmail,
            name: displayName,  // Always have a name
            image: userImage
        )

        print("📝 [Comment] Creating optimistic comment with author: \(author.displayName), image: \(author.image ?? "none")")

        let optimisticComment = Comment(
            id: tempId,
            content: commentContent,
            type: commentType,
            authorId: author.id,
            author: author,
            taskId: taskId,
            createdAt: Date(),
            updatedAt: Date(),
            attachmentUrl: nil,
            attachmentName: attachedFile?.fileName,
            attachmentType: attachedFile?.mimeType,
            attachmentSize: attachedFile?.fileSize,
            parentCommentId: replyingTo?.id,
            replies: nil,
            secureFiles: attachedFile != nil ? [SecureFile(id: attachedFile!.fileId, name: attachedFile!.fileName, size: attachedFile!.fileSize, mimeType: attachedFile!.mimeType)] : nil
        )

        // Add to UI immediately
        let replyToId = replyingTo?.id
        if let replyToId = replyToId {
            // Add as reply
            if let index = comments.firstIndex(where: { $0.id == replyToId }) {
                if comments[index].replies == nil {
                    comments[index].replies = []
                }
                comments[index].replies?.append(optimisticComment)
            }
        } else {
            // Add as top-level comment
            comments.append(optimisticComment)
        }

        // Store fileId before clearing (we need it for the API call)
        var fileIdToSend = attachedFile?.fileId

        // If fileId is a temp ID, get the real fileId (wait if upload not complete)
        if let tempFileId = fileIdToSend, tempFileId.hasPrefix("temp_") {
            if let realFileId = attachmentService.getRealFileId(for: tempFileId) {
                // Upload already complete, use real ID
                fileIdToSend = realFileId
                print("📎 [CommentSection] Using already-uploaded fileId: \(realFileId)")
            } else if attachmentService.isPendingUpload(tempFileId) {
                // Upload still in progress - wait for it
                print("⏳ [CommentSection] Waiting for attachment upload to complete...")
                fileIdToSend = await waitForUploadCompletion(tempFileId: tempFileId)
            }
        }

        // Clear input immediately (feels instant!)
        newCommentText = ""
        attachedFile = nil
        replyingTo = nil
        isTextFieldFocused = false

        isSubmitting = true

        // Make server call in background
        do {
            let newComment = try await commentService.createComment(
                taskId: taskId,
                content: optimisticComment.content,
                type: commentType,
                fileId: fileIdToSend,
                parentCommentId: optimisticComment.parentCommentId,
                authorId: author.id
            )

            // Just update the ID - keep everything else from optimistic comment
            // This preserves author, secureFiles, etc. without complex merging
            let oldTempFileId = optimisticComment.secureFiles?.first?.id

            if let replyToId = replyToId {
                // Update ID in replies
                if let parentIndex = comments.firstIndex(where: { $0.id == replyToId }),
                   let replyIndex = comments[parentIndex].replies?.firstIndex(where: { $0.id == tempId }) {
                    comments[parentIndex].replies?[replyIndex].id = newComment.id
                    // Update secureFiles ID if we have a real file ID
                    if let realFileId = fileIdToSend, !realFileId.hasPrefix("temp_"),
                       let oldId = oldTempFileId {
                        ThumbnailCache.shared.alias(from: oldId, to: realFileId)
                        if let files = comments[parentIndex].replies?[replyIndex].secureFiles {
                            comments[parentIndex].replies?[replyIndex].secureFiles = files.map {
                                SecureFile(id: realFileId, name: $0.name, size: $0.size, mimeType: $0.mimeType)
                            }
                        }
                    }
                }
            } else {
                // Update ID in top-level comments
                if let index = comments.firstIndex(where: { $0.id == tempId }) {
                    comments[index].id = newComment.id
                    // Update secureFiles ID if we have a real file ID
                    if let realFileId = fileIdToSend, !realFileId.hasPrefix("temp_"),
                       let oldId = oldTempFileId {
                        ThumbnailCache.shared.alias(from: oldId, to: realFileId)
                        if let files = comments[index].secureFiles {
                            comments[index].secureFiles = files.map {
                                SecureFile(id: realFileId, name: $0.name, size: $0.size, mimeType: $0.mimeType)
                            }
                        }
                    }
                }
            }

            print("✅ [CommentSection] Server confirmed comment: \(newComment.id)")

        } catch {
            print("❌ [CommentSection] Failed to create comment: \(error)")

            // ROLLBACK: Remove optimistic comment on error
            if let replyToId = replyToId {
                if let parentIndex = comments.firstIndex(where: { $0.id == replyToId }) {
                    comments[parentIndex].replies?.removeAll { $0.id == tempId }
                }
            } else {
                comments.removeAll { $0.id == tempId }
            }
        }

        isSubmitting = false
    }

    // MARK: - File Upload Helpers

    // Maximum file size: 100 MB
    private let maxFileSize = 100 * 1024 * 1024

    private func uploadPhotoItem(_ photoItem: PhotosPickerItem) async {
        isUploadingFile = true
        defer { isUploadingFile = false }

        do {
            print("📸 [CommentSection] Starting photo upload...")

            // Load image data
            guard let imageData = try await photoItem.loadTransferable(type: Data.self) else {
                print("❌ [CommentSection] Failed to load image data from PhotosPicker")
                await MainActor.run {
                    uploadError = "Failed to load photo. Please try again."
                }
                return
            }

            print("📸 [CommentSection] Photo loaded: \(formatFileSize(imageData.count))")

            // Check file size
            if imageData.count > maxFileSize {
                print("❌ [CommentSection] Photo too large: \(formatFileSize(imageData.count)) (max 100 MB)")
                await MainActor.run {
                    uploadError = "Photo is too large (\(formatFileSize(imageData.count))). Maximum size is 100 MB. For larger files, please upload to a file service (Google Drive, Dropbox, etc.) and share a link instead."
                }
                return
            }

            // Get filename
            let fileName = "photo_\(UUID().uuidString).jpg"
            let mimeType = "image/jpeg"

            // Save locally and start async upload - returns immediately with temp fileId
            let tempFileId = attachmentService.saveLocallyAndUploadAsync(
                fileData: imageData,
                fileName: fileName,
                mimeType: mimeType,
                taskId: taskId
            )

            print("📸 [CommentSection] Photo saved locally, uploading in background: \(tempFileId)")

            // Set attached file immediately (no waiting for upload!)
            // UIImage(data:) must run on main thread to avoid "visual style disabled" warnings
            await MainActor.run {
                attachedFile = AttachedFileInfo(
                    fileId: tempFileId,
                    fileName: fileName,
                    fileSize: imageData.count,
                    mimeType: mimeType,
                    imageData: imageData  // For thumbnail preview
                )

                // Pre-cache thumbnail for when comment is posted
                // Already on MainActor, so UIImage(data:) is safe here
                if let uiImage = UIImage(data: imageData) {
                    ThumbnailCache.shared.set(uiImage, for: tempFileId)
                }
            }

        } catch {
            print("❌ [CommentSection] Failed to load photo: \(error)")
            await MainActor.run {
                uploadError = "Failed to load photo: \(error.localizedDescription)"
            }
        }

        // Clear selection
        await MainActor.run {
            selectedPhotoItem = nil
        }
    }

    private func uploadVideoItem(_ videoItem: PhotosPickerItem) async {
        isUploadingFile = true
        defer { isUploadingFile = false }

        do {
            print("🎥 [CommentSection] Starting video upload...")

            // Load video data
            guard let videoData = try await videoItem.loadTransferable(type: Data.self) else {
                print("❌ [CommentSection] Failed to load video data from PhotosPicker")
                await MainActor.run {
                    uploadError = "Failed to load video. Please try again."
                }
                return
            }

            print("🎥 [CommentSection] Video loaded: \(formatFileSize(videoData.count))")

            // Check file size
            if videoData.count > maxFileSize {
                print("❌ [CommentSection] Video too large: \(formatFileSize(videoData.count)) (max 100 MB)")
                await MainActor.run {
                    uploadError = "Video is too large (\(formatFileSize(videoData.count))). Maximum size is 100 MB. For larger files, please upload to a file service (Google Drive, Dropbox, etc.) and share a link instead."
                }
                return
            }

            // Get filename and mime type
            let fileName = "video_\(UUID().uuidString).mp4"
            let mimeType = "video/mp4"

            // Save locally and start async upload - returns immediately with temp fileId
            let tempFileId = attachmentService.saveLocallyAndUploadAsync(
                fileData: videoData,
                fileName: fileName,
                mimeType: mimeType,
                taskId: taskId
            )

            print("🎥 [CommentSection] Video saved locally, uploading in background: \(tempFileId)")

            // Set attached file immediately (no waiting for upload!)
            await MainActor.run {
                attachedFile = AttachedFileInfo(
                    fileId: tempFileId,
                    fileName: fileName,
                    fileSize: videoData.count,
                    mimeType: mimeType,
                    imageData: nil  // No thumbnail for videos
                )
            }

        } catch {
            print("❌ [CommentSection] Failed to load video: \(error)")
            await MainActor.run {
                uploadError = "Failed to load video: \(error.localizedDescription)"
            }
        }

        // Clear selection
        await MainActor.run {
            selectedVideoItem = nil
        }
    }

    private func uploadDocument(_ url: URL) async {
        isUploadingFile = true
        defer { isUploadingFile = false }

        do {
            print("📎 [CommentSection] Starting document upload from: \(url.path)")

            // Access the file
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ [CommentSection] Failed to access document at: \(url.path)")
                await MainActor.run {
                    uploadError = "Failed to access document. Please try again."
                }
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            // Read file data
            let fileData = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let mimeType = attachmentService.getMimeType(for: url.pathExtension)

            print("📎 [CommentSection] File details: name=\(fileName), size=\(fileData.count) bytes, type=\(mimeType)")

            // Check file size
            if fileData.count > maxFileSize {
                print("❌ [CommentSection] Document too large: \(formatFileSize(fileData.count)) (max 100 MB)")
                await MainActor.run {
                    uploadError = "Document is too large (\(formatFileSize(fileData.count))). Maximum size is 100 MB. For larger files, please upload to a file service (Google Drive, Dropbox, etc.) and share a link instead."
                }
                return
            }

            // Save locally and start async upload - returns immediately with temp fileId
            let tempFileId = attachmentService.saveLocallyAndUploadAsync(
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType,
                taskId: taskId
            )

            print("📎 [CommentSection] Document saved locally, uploading in background: \(tempFileId)")

            // Set attached file immediately (no waiting for upload!)
            await MainActor.run {
                attachedFile = AttachedFileInfo(
                    fileId: tempFileId,
                    fileName: fileName,
                    fileSize: fileData.count,
                    mimeType: mimeType,
                    imageData: nil  // No thumbnail for documents
                )
            }

        } catch {
            print("❌ [CommentSection] Failed to load document: \(error)")
            await MainActor.run {
                uploadError = "Failed to load document: \(error.localizedDescription)"
            }
        }
    }

    private func fileIcon(for mimeType: String) -> String {
        let lowercased = mimeType.lowercased()

        if lowercased.hasPrefix("image/") {
            return "photo"
        } else if lowercased.hasPrefix("video/") {
            return "video"
        } else if lowercased.hasPrefix("audio/") {
            return "waveform"
        } else if lowercased.contains("pdf") {
            return "doc.text"
        } else if lowercased.contains("zip") || lowercased.contains("archive") {
            return "archivebox"
        } else {
            return "doc"
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Wait for a pending attachment upload to complete
    private func waitForUploadCompletion(tempFileId: String) async -> String? {
        // Use class-based state to safely share mutable state across closures
        final class State: @unchecked Sendable {
            var observer: NSObjectProtocol?
            var hasResumed = false
        }
        let state = State()

        return await withCheckedContinuation { continuation in
            // Set a timeout of 60 seconds
            let timeoutTask = _Concurrency.Task {
                try? await _Concurrency.Task.sleep(nanoseconds: 60_000_000_000)

                // Check if cancelled or already resumed before proceeding
                guard !_Concurrency.Task.isCancelled && !state.hasResumed else {
                    return
                }

                state.hasResumed = true
                if let obs = state.observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                print("⏰ [CommentSection] Upload timeout for: \(tempFileId)")
                continuation.resume(returning: nil)
            }

            state.observer = NotificationCenter.default.addObserver(
                forName: .attachmentUploadCompleted,
                object: nil,
                queue: .main
            ) { notification in
                guard let userInfo = notification.userInfo,
                      let notificationTempId = userInfo["tempFileId"] as? String,
                      notificationTempId == tempFileId,
                      let realFileId = userInfo["realFileId"] as? String else {
                    return
                }

                // Guard against double-resume
                guard !state.hasResumed else {
                    return
                }
                state.hasResumed = true

                // Cancel timeout
                timeoutTask.cancel()

                // Remove observer
                if let obs = state.observer {
                    NotificationCenter.default.removeObserver(obs)
                }

                print("✅ [CommentSection] Upload completed, got fileId: \(realFileId)")
                continuation.resume(returning: realFileId)
            }
        }
    }
}

struct CommentRowViewEnhanced: View {
    let comment: Comment
    let allTaskFiles: [SecureFile]
    let colorScheme: ColorScheme
    let useMarkdown: Bool
    let isOffline: Bool  // When offline, treat all cached comments as user comments
    let onReply: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteAlert = false
    // Don't use @StateObject here - it causes re-renders when isLoading changes
    // Just access the shared instance directly for delete operations

    // Check if this is a system comment (no authorId)
    // When offline, don't treat nil authorId as system comment (cached data issue)
    private var isSystemComment: Bool {
        if isOffline {
            return false  // Render all cached comments as user comments
        }
        return comment.authorId == nil
    }

    var body: some View {
        // System comments use discreet formatting (like timestamp)
        if isSystemComment {
            Text(comment.createdAt != nil ? "On \(formatSystemCommentDate(comment.createdAt!)), \(comment.content)" : comment.content)
                .font(Theme.Typography.caption2())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        } else {
            // Regular comment with full formatting
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                // Header
                HStack {
                    // Author section (tappable to view profile)
                    NavigationLink(destination: UserProfileView(userId: comment.authorId ?? "")) {
                        HStack(spacing: Theme.spacing8) {
                            // Author avatar (cached for offline)
                            CachedAsyncImage(url: comment.author?.cachedImageURL.flatMap { URL(string: $0) }) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ZStack {
                                    Circle()
                                        .fill(Theme.accent)
                                    Text(comment.author?.initials ?? "?")
                                        .font(Theme.Typography.caption1())
                                        .foregroundColor(Theme.accentText)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(comment.author?.displayName ?? "Unknown")
                                    .font(Theme.Typography.caption1())
                                    .fontWeight(.semibold)
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                                if let createdAt = comment.createdAt {
                                    Text(formatCommentDate(createdAt))
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Sync status indicator - only show when offline with temp ID
                    // When online, sync happens fast enough that we don't need to show it
                    if comment.id.hasPrefix("temp_") && isOffline {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                            Text("Pending")
                                .font(Theme.Typography.caption2())
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Menu {
                        Button {
                            onReply()
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                        }

                        if comment.authorId == AuthManager.shared.userId {
                            Button(role: .destructive) {
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    }
                }

            // Attachments (show first, like web)
            if let secureFiles = comment.secureFiles, !secureFiles.isEmpty {
                AttachmentGridView(files: secureFiles, allTaskFiles: allTaskFiles, colorScheme: colorScheme)
                    .padding(.bottom, Theme.spacing4)
            }

            // Content (only show if not empty, like web)
            if !comment.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if useMarkdown && (comment.type == .MARKDOWN || comment.content.containsMarkdown) {
                    Text(comment.content.attributedMarkdown())
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                } else {
                    Text(comment.content)
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                }
            }

            // Replies
            if let replies = comment.replies, !replies.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    ForEach(replies) { reply in
                        CommentRowViewEnhanced(
                            comment: reply,
                            allTaskFiles: allTaskFiles,
                            colorScheme: colorScheme,
                            useMarkdown: useMarkdown,
                            isOffline: isOffline,
                            onReply: onReply,
                            onDelete: onDelete
                        )
                        .padding(.leading, Theme.spacing16)
                    }
                }
            }
        }
        .padding(Theme.spacing12)
            .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .alert(NSLocalizedString("comments.delete_comment", comment: "Delete Comment"), isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    do {
                        // Delete from UI immediately (optimistic update)
                        onDelete()
                        // Delete from server (use shared instance directly)
                        try await CommentService.shared.deleteComment(id: comment.id)
                        print("✅ Comment deleted successfully")
                    } catch {
                        print("❌ Delete comment failed: \(error)")
                        // Note: In a production app, you might want to revert the UI change on error
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this comment?")
        }
    }
}

}

// MARK: - Helper Functions

private func formatCommentDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()

    // Check if date is today
    if calendar.isDateInToday(date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    // Check if date is this year
    if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    // Date from previous year
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy, h:mm a"
    return formatter.string(from: date)
}

private func formatSystemCommentDate(_ date: Date) -> String {
    // Format: "Nov 19 at 6:30 PM" (compact format for system comments)
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d 'at' h:mm a"
    return formatter.string(from: date)
}

struct AttachmentGridView: View {
    let files: [SecureFile]
    let allTaskFiles: [SecureFile]
    let colorScheme: ColorScheme

    @State private var selectedIndex: Int = 0
    @State private var isShowingQuickLook = false
    @State private var previewItems: [(fileId: String, url: URL)] = []
    @State private var isPreparingPreview = false

    var body: some View {
        // Use GeometryReader to get actual container width (critical for iPad popovers)
        GeometryReader { geometry in
            let availableWidth = geometry.size.width > 0 ? geometry.size.width : 300

            VStack(alignment: .leading, spacing: 4) {
                if files.count == 1 {
                    // Single file: Full bleed if image/video
                    let file = files[0]
                    AttachmentThumbnail(
                        file: file,
                        colorScheme: colorScheme,
                        size: availableWidth, // Use actual container width
                        contentMode: .fit,
                        showDetails: !isMedia(file),
                        onTap: {
                            prepareAndShowPreview(for: file)
                        }
                        // No onEdit needed - QuickLook handles markup and saves to Astrid
                    )
                } else {
                    // Multiple files: Grid
                    let columns = [
                        GridItem(.flexible(), spacing: 4),
                        GridItem(.flexible(), spacing: 4)
                    ]

                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(0..<files.count, id: \.self) { index in
                            AttachmentThumbnail(
                                file: files[index],
                                colorScheme: colorScheme,
                                size: (availableWidth - 4) / 2, // Half width minus spacing
                                contentMode: .fill,
                                showDetails: !isMedia(files[index]),
                                onTap: {
                                    prepareAndShowPreview(for: files[index])
                                }
                                // No onEdit needed - QuickLook handles markup and saves to Astrid
                            )
                        }
                    }
                }
            }
        }
        // Provide a fixed height based on the number of files to prevent layout issues
        .frame(height: files.count == 1 ? 200 : (files.count <= 2 ? 120 : (CGFloat((files.count + 1) / 2) * 124)))
        // Use UIKit-based QuickLook presentation for proper toolbar support
        .quickLookPresenter(items: previewItems, initialIndex: selectedIndex, isPresented: $isShowingQuickLook)
        .overlay {
            if isPreparingPreview {
                ZStack {
                    Color.black.opacity(0.2)
                    ProgressView()
                        .tint(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private func isMedia(_ file: SecureFile) -> Bool {
        let mime = file.mimeType.lowercased()
        return mime.hasPrefix("image/") || mime.hasPrefix("video/")
    }

    private func prepareAndShowPreview(for file: SecureFile) {
        isPreparingPreview = true

        _Concurrency.Task {
            let results = await AttachmentService.shared.prepareFilesForPreview(files: allTaskFiles)
            await MainActor.run {
                // Store full items with file IDs for save support
                self.previewItems = results

                // Find the index of the selected file in the successfully prepared URLs
                if let index = results.firstIndex(where: { $0.fileId == file.id }) {
                    self.selectedIndex = index
                } else {
                    self.selectedIndex = 0
                }

                self.isPreparingPreview = false
                if !previewItems.isEmpty {
                    self.isShowingQuickLook = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        CommentSectionViewEnhanced(taskId: "sample-task-id")
            .padding()
    }
}
