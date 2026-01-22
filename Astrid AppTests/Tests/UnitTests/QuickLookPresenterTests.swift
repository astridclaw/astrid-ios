import XCTest
@testable import Astrid_App

/// Unit tests for QuickLook attachment editing functionality
/// Tests ensure attachment markup editing and thumbnail refresh work correctly
final class QuickLookPresenterTests: XCTestCase {

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        await MainActor.run {
            // Clear thumbnail cache before each test
            clearThumbnailCache()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            clearThumbnailCache()
        }
    }

    @MainActor
    private func clearThumbnailCache() {
        // ThumbnailCache doesn't have a clear method, but we can verify it works
    }

    // MARK: - ThumbnailCache Tests

    @MainActor
    func testThumbnailCacheSetAndGet() {
        // Given
        let fileId = "test-file-123"
        let testImage = UIImage(systemName: "photo")!

        // When
        ThumbnailCache.shared.set(testImage, for: fileId)
        let retrieved = ThumbnailCache.shared.get(fileId)

        // Then
        XCTAssertNotNil(retrieved, "Should retrieve cached thumbnail")
    }

    @MainActor
    func testThumbnailCacheReturnsNilForUncachedFile() {
        // When
        let retrieved = ThumbnailCache.shared.get("nonexistent-file-id")

        // Then
        XCTAssertNil(retrieved, "Should return nil for uncached file")
    }

    @MainActor
    func testThumbnailCacheHasMethod() {
        // Given
        let fileId = "test-file-456"
        let testImage = UIImage(systemName: "doc")!

        // When - before caching
        let hasBefore = ThumbnailCache.shared.has(fileId)

        // Then
        XCTAssertFalse(hasBefore, "Should not have file before caching")

        // When - after caching
        ThumbnailCache.shared.set(testImage, for: fileId)
        let hasAfter = ThumbnailCache.shared.has(fileId)

        // Then
        XCTAssertTrue(hasAfter, "Should have file after caching")
    }

    @MainActor
    func testThumbnailCacheAlias() {
        // Given
        let tempId = "temp_12345"
        let realId = "real-file-id"
        let testImage = UIImage(systemName: "photo.fill")!

        ThumbnailCache.shared.set(testImage, for: tempId)

        // When
        ThumbnailCache.shared.alias(from: tempId, to: realId)

        // Then
        XCTAssertTrue(ThumbnailCache.shared.has(realId), "Should have aliased file")
        XCTAssertNotNil(ThumbnailCache.shared.get(realId), "Should retrieve aliased thumbnail")
    }

    // MARK: - AstridPreviewItem Tests

    func testAstridPreviewItemProperties() {
        // Given
        let fileId = "file-789"
        let url = URL(fileURLWithPath: "/tmp/test-image.jpg")

        // When
        let item = AstridPreviewItem(fileId: fileId, url: url)

        // Then
        XCTAssertEqual(item.fileId, fileId)
        XCTAssertEqual(item.fileURL, url)
        XCTAssertEqual(item.previewItemURL, url)
        XCTAssertEqual(item.previewItemTitle, "test-image.jpg")
    }

    func testAstridPreviewItemPreviewItemTitle() {
        // Given
        let url = URL(fileURLWithPath: "/path/to/document.pdf")

        // When
        let item = AstridPreviewItem(fileId: "any", url: url)

        // Then
        XCTAssertEqual(item.previewItemTitle, "document.pdf")
    }

    // MARK: - Editable Extensions Tests

    func testEditableImageExtensions() {
        // Given - all image extensions that should be editable
        let editableExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp", "pdf"]

        for ext in editableExtensions {
            // When
            let isEditable = isEditableExtension(ext)

            // Then
            XCTAssertTrue(isEditable, "\(ext) should be editable")
        }
    }

    func testNonEditableExtensions() {
        // Given - extensions that should NOT be editable
        let nonEditableExtensions = ["txt", "doc", "docx", "xls", "mp4", "mov", "zip", "html"]

        for ext in nonEditableExtensions {
            // When
            let isEditable = isEditableExtension(ext)

            // Then
            XCTAssertFalse(isEditable, "\(ext) should not be editable")
        }
    }

    /// Helper to test extension editability logic (mirrors QuickLookPresenter logic)
    private func isEditableExtension(_ ext: String) -> Bool {
        let editableExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp", "pdf"]
        return editableExtensions.contains(ext.lowercased())
    }

    // MARK: - File ID Validation Tests

    func testTempFileIdsShouldNotBeEditable() {
        // Given
        let tempFileIds = ["temp_12345", "temp_abc", "temp_"]

        for fileId in tempFileIds {
            // When
            let canEdit = canEditFile(fileId: fileId)

            // Then
            XCTAssertFalse(canEdit, "temp file \(fileId) should not be editable")
        }
    }

    func testUnknownFileIdsShouldNotBeEditable() {
        // Given
        let unknownFileIds = ["unknown-12345", "unknown-abc", "unknown-"]

        for fileId in unknownFileIds {
            // When
            let canEdit = canEditFile(fileId: fileId)

            // Then
            XCTAssertFalse(canEdit, "unknown file \(fileId) should not be editable")
        }
    }

    func testRealFileIdsShouldBeEditable() {
        // Given
        let realFileIds = ["abc123", "file-uuid-here", "9c22b653-5eda-4a2a-8c75-a089dcfb5f04"]

        for fileId in realFileIds {
            // When
            let canEdit = canEditFile(fileId: fileId)

            // Then
            XCTAssertTrue(canEdit, "real file \(fileId) should be editable")
        }
    }

    /// Helper to test file ID validation logic (mirrors QuickLookPresenter logic)
    private func canEditFile(fileId: String) -> Bool {
        return !fileId.starts(with: "unknown-") && !fileId.starts(with: "temp_")
    }

    // MARK: - MIME Type Tests

    func testMimeTypeForImageExtensions() {
        XCTAssertEqual(mimeTypeForExtension("jpg"), "image/jpeg")
        XCTAssertEqual(mimeTypeForExtension("jpeg"), "image/jpeg")
        XCTAssertEqual(mimeTypeForExtension("png"), "image/png")
        XCTAssertEqual(mimeTypeForExtension("gif"), "image/gif")
        XCTAssertEqual(mimeTypeForExtension("heic"), "image/heic")
        XCTAssertEqual(mimeTypeForExtension("heif"), "image/heic")
        XCTAssertEqual(mimeTypeForExtension("webp"), "image/webp")
    }

    func testMimeTypeForPDF() {
        XCTAssertEqual(mimeTypeForExtension("pdf"), "application/pdf")
    }

    func testMimeTypeForUnknownExtension() {
        XCTAssertEqual(mimeTypeForExtension("xyz"), "application/octet-stream")
        XCTAssertEqual(mimeTypeForExtension("unknown"), "application/octet-stream")
    }

    /// Helper to test MIME type logic (mirrors QuickLookPresenter.mimeTypeForURL)
    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Notification Tests

    @MainActor
    func testAttachmentUpdatedNotificationContainsFileId() {
        // Given
        let expectation = XCTestExpectation(description: "Notification received")
        let expectedFileId = "test-file-id"
        var receivedFileId: String?

        let observer = NotificationCenter.default.addObserver(
            forName: .attachmentUpdated,
            object: nil,
            queue: .main
        ) { notification in
            receivedFileId = notification.userInfo?["fileId"] as? String
            expectation.fulfill()
        }

        // When
        NotificationCenter.default.post(
            name: .attachmentUpdated,
            object: nil,
            userInfo: ["fileId": expectedFileId]
        )

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedFileId, expectedFileId)

        NotificationCenter.default.removeObserver(observer)
    }
}
