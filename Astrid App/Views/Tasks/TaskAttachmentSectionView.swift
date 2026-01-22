import SwiftUI
import QuickLook

struct TaskAttachmentSectionView: View {
    let task: Task
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var commentService = CommentService.shared

    // Preview state - now tracks file IDs for save-to-Astrid support
    @State private var previewItems: [(fileId: String, url: URL)] = []
    @State private var selectedIndex: Int = 0
    @State private var isPreparingPreview = false
    @State private var showQuickLook = false

    private var allFiles: [SecureFile] {
        var files: [SecureFile] = []

        // 1. Add direct task attachments
        if let directFiles = task.secureFiles {
            files.append(contentsOf: directFiles)
        }

        // 2. Add legacy attachments (if any, converted to SecureFile)
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

        // 3. Add files from comments (using CommentService cache)
        if let comments = commentService.cachedComments[task.id] {
            for comment in comments {
                if let commentFiles = comment.secureFiles {
                    files.append(contentsOf: commentFiles)
                }
            }
        }

        // Remove duplicates by ID
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

    var body: some View {
        let files = allFiles

        if !files.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(String(format: NSLocalizedString("attachments.count", comment: "Attachments count"), files.count))
                    .font(Theme.Typography.footnote())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    .padding(.horizontal, Theme.spacing16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spacing12) {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            AttachmentThumbnail(
                                file: file,
                                colorScheme: colorScheme,
                                size: 64,
                                showDetails: false,
                                onTap: {
                                    prepareAndShowPreview(files: files, selectedFileId: file.id)
                                }
                                // No onEdit needed - QuickLook handles markup and saves to Astrid
                            )
                        }
                    }
                    .padding(.horizontal, Theme.spacing16)
                }

                Divider()
                    .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)
                    .padding(.top, Theme.spacing8)
            }
            .overlay {
                if isPreparingPreview {
                    ZStack {
                        Color.black.opacity(0.2)
                        ProgressView()
                            .tint(Theme.accent)
                    }
                    .edgesIgnoringSafeArea(.all)
                }
            }
            // Use UIKit-based QuickLook presentation for proper toolbar support
            .quickLookPresenter(items: previewItems, initialIndex: selectedIndex, isPresented: $showQuickLook)
        }
    }

    private func prepareAndShowPreview(files: [SecureFile], selectedFileId: String) {
        isPreparingPreview = true

        _Concurrency.Task {
            let results = await AttachmentService.shared.prepareFilesForPreview(files: files)
            await MainActor.run {
                // Store the full items with file IDs for save support
                self.previewItems = results

                // Find the index of the selected file in the successfully prepared URLs
                if let index = results.firstIndex(where: { $0.fileId == selectedFileId }) {
                    self.selectedIndex = index
                } else {
                    self.selectedIndex = 0
                }

                self.isPreparingPreview = false
                if !previewItems.isEmpty {
                    self.showQuickLook = true
                }
            }
        }
    }
}
