import Foundation
import UIKit
import UniformTypeIdentifiers
import Combine

/// Info about a locally cached attachment pending upload
struct PendingAttachment: Codable {
    let tempFileId: String
    let localPath: String
    let fileName: String
    let mimeType: String
    let fileSize: Int
    let taskId: String
    var realFileId: String?  // Set when upload completes
    var uploadStatus: UploadStatus

    enum UploadStatus: String, Codable {
        case pending
        case uploading
        case completed
        case failed
    }
}

@MainActor
class AttachmentService: ObservableObject {
    static let shared = AttachmentService(apiClient: APIClient.shared)

    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var errorMessage: String?
    @Published var pendingUploads: [String: PendingAttachment] = [:]  // tempFileId -> PendingAttachment

    private let apiClient: APIClientProtocol
    private let fileManager = FileManager.default
    private let cacheDirectory: URL  // For pending uploads
    private let downloadCacheDirectory: URL  // For downloaded/viewed attachments

    // Map temp fileIds to real fileIds after upload
    private var fileIdMapping: [String: String] = [:]

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient

        // Setup local cache directory for pending attachments
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("PendingAttachments", isDirectory: true)
        downloadCacheDirectory = cachesDirectory.appendingPathComponent("DownloadedAttachments", isDirectory: true)

        // Create cache directories if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: downloadCacheDirectory, withIntermediateDirectories: true)

        print("📦 [AttachmentService] Pending cache: \(cacheDirectory.path)")
        print("📦 [AttachmentService] Download cache: \(downloadCacheDirectory.path)")

        // Load any pending uploads from previous session
        loadPendingUploads()
    }

    // MARK: - Local File Cache

    /// Save file locally and return temp fileId immediately
    /// Upload happens asynchronously in background
    func saveLocallyAndUploadAsync(
        fileData: Data,
        fileName: String,
        mimeType: String,
        taskId: String
    ) -> String {
        let tempFileId = "temp_\(UUID().uuidString)"
        let localPath = cacheDirectory.appendingPathComponent(tempFileId).path

        // Save file locally
        do {
            try fileData.write(to: URL(fileURLWithPath: localPath))
            print("💾 [AttachmentService] Saved file locally: \(tempFileId) (\(fileData.count) bytes)")
        } catch {
            print("❌ [AttachmentService] Failed to save file locally: \(error)")
            return tempFileId
        }

        // Create pending attachment record
        let pending = PendingAttachment(
            tempFileId: tempFileId,
            localPath: localPath,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: fileData.count,
            taskId: taskId,
            realFileId: nil,
            uploadStatus: .pending
        )

        pendingUploads[tempFileId] = pending
        savePendingUploads()

        // Start background upload
        _Concurrency.Task {
            await uploadPendingAttachment(tempFileId: tempFileId)
        }

        return tempFileId
    }

    /// Get the real fileId for a temp fileId (if upload completed)
    func getRealFileId(for tempFileId: String) -> String? {
        return fileIdMapping[tempFileId] ?? pendingUploads[tempFileId]?.realFileId
    }

    /// Check if a fileId is a temp ID that's still pending
    func isPendingUpload(_ fileId: String) -> Bool {
        guard fileId.hasPrefix("temp_") else { return false }
        if let pending = pendingUploads[fileId] {
            return pending.uploadStatus != .completed
        }
        return false
    }

    /// Get local file data for a temp fileId
    func getLocalFileData(for tempFileId: String) -> Data? {
        guard let pending = pendingUploads[tempFileId] else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: pending.localPath))
    }

    // MARK: - Downloaded Attachments Cache (for offline viewing)

    /// Get cached download data for a fileId
    func getCachedDownload(for fileId: String) -> Data? {
        let cachedPath = downloadCacheDirectory.appendingPathComponent(fileId)
        guard fileManager.fileExists(atPath: cachedPath.path) else { return nil }
        return try? Data(contentsOf: cachedPath)
    }

    /// Save downloaded data to cache
    func cacheDownload(fileId: String, data: Data) {
        let cachedPath = downloadCacheDirectory.appendingPathComponent(fileId)
        do {
            try data.write(to: cachedPath)
            print("💾 [AttachmentService] Cached download: \(fileId) (\(data.count) bytes)")
        } catch {
            print("⚠️ [AttachmentService] Failed to cache download: \(error)")
        }
    }

    /// Check if a download is cached
    func hasDownloadCached(for fileId: String) -> Bool {
        let cachedPath = downloadCacheDirectory.appendingPathComponent(fileId)
        return fileManager.fileExists(atPath: cachedPath.path)
    }

    /// Get cached file URL for QuickLook preview
    func getCachedFileURL(for fileId: String, fileName: String) -> URL? {
        let cachedPath = downloadCacheDirectory.appendingPathComponent(fileId)
        guard fileManager.fileExists(atPath: cachedPath.path) else { return nil }

        // Create a temp file with the proper extension for QuickLook
        let tempDir = fileManager.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(fileName)

        do {
            // Remove existing temp file if any
            try? fileManager.removeItem(at: tempFile)
            // Copy cached file to temp with proper name
            try fileManager.copyItem(at: cachedPath, to: tempFile)
            return tempFile
        } catch {
            print("⚠️ [AttachmentService] Failed to prepare cached file for preview: \(error)")
            return nil
        }
    }

    /// Get the signed download URL for a secure file
    func getSecureFileDownloadURL(for fileId: String) async throws -> URL? {
        let infoURL = "\(Constants.API.baseURL)/api/secure-files/\(fileId)?info=true"
        guard let url = URL(string: infoURL) else { return nil }
        
        var request = URLRequest(url: url)
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        
        let (infoData, infoResponse) = try await URLSession.shared.data(for: request)
        guard let httpResponse = infoResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        
        struct FileInfo: Codable { let url: String }
        let fileInfo = try JSONDecoder().decode(FileInfo.self, from: infoData)
        
        return URL(string: fileInfo.url)
    }

    /// Prepare multiple files for preview
    func prepareFilesForPreview(files: [SecureFile]) async -> [(fileId: String, url: URL)] {
        var results: [(fileId: String, url: URL)] = []
        
        for file in files {
            // 1. Check if it's a temp file
            if file.id.hasPrefix("temp_") {
                if let localData = getLocalFileData(for: file.id) {
                    let tempDir = fileManager.temporaryDirectory
                    let tempFileURL = tempDir.appendingPathComponent(file.name)
                    try? localData.write(to: tempFileURL)
                    results.append((fileId: file.id, url: tempFileURL))
                }
                continue
            }
            
            // 2. Check disk cache
            if let cachedURL = getCachedFileURL(for: file.id, fileName: file.name) {
                results.append((fileId: file.id, url: cachedURL))
                continue
            }
            
            // 3. Download if not cached
            do {
                let infoURL = "\(Constants.API.baseURL)/api/secure-files/\(file.id)?info=true"
                guard let url = URL(string: infoURL) else { continue }
                
                var request = URLRequest(url: url)
                if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                    request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
                }
                
                let (infoData, infoResponse) = try await URLSession.shared.data(for: request)
                guard let httpResponse = infoResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { continue }
                
                struct FileInfo: Codable { let url: String }
                let fileInfo = try JSONDecoder().decode(FileInfo.self, from: infoData)
                
                guard let downloadURL = URL(string: fileInfo.url) else { continue }
                let (fileData, _) = try await URLSession.shared.data(from: downloadURL)
                
                cacheDownload(fileId: file.id, data: fileData)
                
                let tempDir = fileManager.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent(file.name)
                try? fileData.write(to: tempFileURL)
                results.append((fileId: file.id, url: tempFileURL))
            } catch {
                print("❌ [AttachmentService] Failed to download file for multi-preview: \(error)")
            }
        }
        
        return results
    }

    /// Cancel a pending upload and clean up local file
    func cancelUpload(tempFileId: String) {
        guard let pending = pendingUploads[tempFileId] else {
            print("⚠️ [AttachmentService] No pending upload to cancel: \(tempFileId)")
            return
        }

        print("🗑️ [AttachmentService] Cancelling upload: \(tempFileId)")

        // Delete local file
        try? fileManager.removeItem(atPath: pending.localPath)

        // Remove from pending uploads
        pendingUploads.removeValue(forKey: tempFileId)
        fileIdMapping.removeValue(forKey: tempFileId)
        savePendingUploads()

        print("✅ [AttachmentService] Upload cancelled and cleaned up: \(tempFileId)")
    }

    /// Upload a pending attachment
    private func uploadPendingAttachment(tempFileId: String) async {
        guard var pending = pendingUploads[tempFileId] else {
            print("⚠️ [AttachmentService] Pending attachment not found: \(tempFileId)")
            return
        }

        // Update status
        pending.uploadStatus = .uploading
        pendingUploads[tempFileId] = pending
        savePendingUploads()

        print("📤 [AttachmentService] Starting upload for: \(tempFileId)")

        do {
            // Load file data
            let fileData = try Data(contentsOf: URL(fileURLWithPath: pending.localPath))

            // Upload to server
            let realFileId = try await uploadToSecureEndpoint(
                fileData: fileData,
                fileName: pending.fileName,
                mimeType: pending.mimeType,
                taskId: pending.taskId
            )

            // Update mapping and status
            fileIdMapping[tempFileId] = realFileId
            pending.realFileId = realFileId
            pending.uploadStatus = .completed
            pendingUploads[tempFileId] = pending
            savePendingUploads()

            print("✅ [AttachmentService] Upload completed: \(tempFileId) -> \(realFileId)")

            // Notify that upload completed
            NotificationCenter.default.post(
                name: .attachmentUploadCompleted,
                object: nil,
                userInfo: ["tempFileId": tempFileId, "realFileId": realFileId]
            )

            // Clean up local file after successful upload
            try? fileManager.removeItem(atPath: pending.localPath)

        } catch {
            print("❌ [AttachmentService] Upload failed: \(error)")
            pending.uploadStatus = .failed
            pendingUploads[tempFileId] = pending
            savePendingUploads()
        }
    }

    /// Retry all failed uploads
    func retryFailedUploads() {
        for (tempFileId, pending) in pendingUploads where pending.uploadStatus == .failed {
            _Concurrency.Task {
                await uploadPendingAttachment(tempFileId: tempFileId)
            }
        }
    }

    // MARK: - Persistence

    private func savePendingUploads() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(pendingUploads) {
            UserDefaults.standard.set(data, forKey: "pendingAttachments")
        }
    }

    private func loadPendingUploads() {
        guard let data = UserDefaults.standard.data(forKey: "pendingAttachments") else { return }
        let decoder = JSONDecoder()
        if let loaded = try? decoder.decode([String: PendingAttachment].self, from: data) {
            pendingUploads = loaded

            // Build fileId mapping from completed uploads
            for (tempId, pending) in loaded {
                if let realId = pending.realFileId {
                    fileIdMapping[tempId] = realId
                }
            }

            // Retry any pending/failed uploads
            for (tempFileId, pending) in loaded where pending.uploadStatus == .pending || pending.uploadStatus == .failed {
                _Concurrency.Task {
                    await uploadPendingAttachment(tempFileId: tempFileId)
                }
            }

            print("📦 [AttachmentService] Loaded \(loaded.count) pending uploads")
        }
    }
    
    // MARK: - Upload

    func uploadAttachment(taskId: String, fileData: Data, fileName: String, mimeType: String) async throws -> Attachment {
        isUploading = true
        uploadProgress = 0
        errorMessage = nil

        defer { isUploading = false }

        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Create request
        let url = URL(string: Constants.API.baseURL + "/api/tasks/\(taskId)/attachments")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Note: Do NOT set httpBody when using upload(for:from:) - pass body data directly to upload method

        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        // Upload with progress - body is passed here, not set on request.httpBody
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        // Parse response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let attachment = try decoder.decode(Attachment.self, from: data)

        uploadProgress = 1.0
        return attachment
    }

    // MARK: - Secure Upload (for comments)

    /// Upload file to secure storage endpoint for use with comments
    /// Returns fileId that can be associated with a comment
    ///
    /// For files larger than 4MB, uses direct upload to Vercel Blob:
    /// 1. Request upload URL from server (validates permissions, generates token)
    /// 2. PUT file directly to Vercel Blob (bypasses serverless size limits)
    /// 3. Server callback stores metadata
    func uploadToSecureEndpoint(fileData: Data, fileName: String, mimeType: String, taskId: String) async throws -> String {
        isUploading = true
        uploadProgress = 0
        errorMessage = nil

        defer { isUploading = false }

        // For files larger than 4MB, use direct upload to bypass serverless limits
        let fileSizeMB = Double(fileData.count) / (1024 * 1024)
        if fileSizeMB > 4.0 {
            print("📦 [AttachmentService] Large file detected (\(String(format: "%.1f", fileSizeMB)) MB), using direct upload")
            return try await uploadDirectToBlob(fileData: fileData, fileName: fileName, mimeType: mimeType, taskId: taskId)
        }

        // For smaller files, use the original server-side upload
        return try await uploadViaServer(fileData: fileData, fileName: fileName, mimeType: mimeType, taskId: taskId)
    }

    /// Upload directly to Vercel Blob using a client token (for large files)
    private func uploadDirectToBlob(fileData: Data, fileName: String, mimeType: String, taskId: String) async throws -> String {
        // Step 1: Get upload URL and token from server
        print("📡 [AttachmentService] Step 1: Requesting upload URL...")

        let getUrlEndpoint = URL(string: Constants.API.baseURL + "/api/secure-upload/get-upload-url")!
        var getUrlRequest = URLRequest(url: getUrlEndpoint)
        getUrlRequest.httpMethod = "POST"
        getUrlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            getUrlRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        } else {
            print("⚠️ [AttachmentService] WARNING: No session cookie found!")
            throw AttachmentError.uploadFailed
        }

        // Request body with file metadata
        let requestBody: [String: Any] = [
            "fileName": fileName,
            "fileType": mimeType,
            "fileSize": fileData.count,
            "context": ["taskId": taskId]
        ]
        getUrlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (urlData, urlResponse) = try await URLSession.shared.data(for: getUrlRequest)

        guard let httpResponse = urlResponse as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: urlData, encoding: .utf8) {
                print("❌ [AttachmentService] Failed to get upload URL: \(responseString)")
            }
            throw AttachmentError.uploadFailed
        }

        // Parse response to get upload URL and token
        struct UploadUrlResponse: Codable {
            let uploadToken: String
            let pathname: String
            let fileId: String
            let uploadUrl: String
        }

        let decoder = JSONDecoder()
        let uploadUrlResponse = try decoder.decode(UploadUrlResponse.self, from: urlData)

        print("✅ [AttachmentService] Got upload URL for file: \(uploadUrlResponse.fileId)")
        uploadProgress = 0.1

        // Step 2: Upload file directly to Vercel Blob
        print("📡 [AttachmentService] Step 2: Uploading to Vercel Blob...")

        var blobRequest = URLRequest(url: URL(string: uploadUrlResponse.uploadUrl)!)
        blobRequest.httpMethod = "PUT"
        // Vercel Blob expects the client token in the Authorization header
        blobRequest.setValue("Bearer \(uploadUrlResponse.uploadToken)", forHTTPHeaderField: "Authorization")
        blobRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        blobRequest.setValue("public, max-age=31536000", forHTTPHeaderField: "x-cache-control-max-age")

        // Use upload delegate to track progress
        let delegate = UploadProgressDelegate(onProgress: { [weak self] progress in
            _Concurrency.Task { @MainActor in
                // Progress from 0.1 to 0.9 during upload
                self?.uploadProgress = 0.1 + (progress * 0.8)
            }
        })

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (blobData, blobResponse) = try await session.upload(for: blobRequest, from: fileData)

        guard let blobHttpResponse = blobResponse as? HTTPURLResponse else {
            print("❌ [AttachmentService] Invalid blob response type")
            throw AttachmentError.uploadFailed
        }

        print("📡 [AttachmentService] Blob upload status: \(blobHttpResponse.statusCode)")

        guard (200...299).contains(blobHttpResponse.statusCode) else {
            if let responseString = String(data: blobData, encoding: .utf8) {
                print("❌ [AttachmentService] Blob upload failed: \(responseString)")
            }
            throw AttachmentError.uploadFailed
        }

        print("✅ [AttachmentService] File uploaded directly to Vercel Blob")
        uploadProgress = 1.0

        return uploadUrlResponse.fileId
    }

    /// Upload via server (for smaller files)
    private func uploadViaServer(fileData: Data, fileName: String, mimeType: String, taskId: String) async throws -> String {
        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // Add context field
        let contextJSON = """
        {"taskId":"\(taskId)"}
        """
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"context\"\r\n\r\n".data(using: .utf8)!)
        body.append(contextJSON.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Create request to secure upload endpoint
        let url = URL(string: Constants.API.baseURL + "/api/secure-upload/request-upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Note: Do NOT set httpBody when using upload(for:from:) - pass body data directly to upload method

        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            print("🍪 [AttachmentService] Using session cookie: \(sessionCookie.prefix(50))...")
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        } else {
            print("⚠️ [AttachmentService] WARNING: No session cookie found!")
        }

        print("📡 [AttachmentService] Uploading to: \(url.absoluteString)")
        print("📡 [AttachmentService] Request headers: \(request.allHTTPHeaderFields ?? [:])")

        // Upload - body is passed here, not set on request.httpBody
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [AttachmentService] Invalid response type")
            throw AttachmentError.uploadFailed
        }

        print("📡 [AttachmentService] Upload response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            // Log response body for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [AttachmentService] Upload failed with status \(httpResponse.statusCode)")
                print("❌ [AttachmentService] Response body: \(responseString)")
            }
            throw AttachmentError.uploadFailed
        }

        // Parse response to get fileId
        struct SecureUploadResponse: Codable {
            let fileId: String
            let fileName: String
            let fileSize: Int
            let mimeType: String
            let success: Bool
        }

        let decoder = JSONDecoder()
        let uploadResponse = try decoder.decode(SecureUploadResponse.self, from: data)

        uploadProgress = 1.0
        return uploadResponse.fileId
    }
    
    // MARK: - Download
    
    func downloadAttachment(_ attachment: Attachment) async throws -> Data {
        guard let url = URL(string: attachment.url) else {
            throw AttachmentError.invalidURL
        }
        
        var request = URLRequest(url: url)
        
        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        return data
    }
    
    // MARK: - Update (for edited attachments)

    /// Update an existing secure file with new content (e.g., after markup editing)
    /// Uses direct upload to Vercel Blob to bypass serverless function payload limits
    /// Returns the updated file info
    func updateAttachment(fileId: String, newFileData: Data, mimeType: String) async throws -> SecureFile {
        isUploading = true
        uploadProgress = 0
        errorMessage = nil

        defer { isUploading = false }

        print("📤 [AttachmentService] Updating file: \(fileId) (\(newFileData.count) bytes)")

        // Get session cookie
        guard let sessionCookie = try? KeychainService.shared.getSessionCookie() else {
            print("⚠️ [AttachmentService] WARNING: No session cookie found!")
            throw AttachmentError.uploadFailed
        }

        // Step 1: Request upload URL from server
        print("📤 [AttachmentService] Step 1: Getting upload URL...")
        let uploadUrlEndpoint = URL(string: Constants.API.baseURL + "/api/secure-files/\(fileId)/upload-url")!
        var uploadUrlRequest = URLRequest(url: uploadUrlEndpoint)
        uploadUrlRequest.httpMethod = "POST"
        uploadUrlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        uploadUrlRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        uploadUrlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "mimeType": mimeType,
            "fileSize": newFileData.count
        ])

        let (uploadUrlData, uploadUrlResponse) = try await URLSession.shared.data(for: uploadUrlRequest)

        guard let httpResponse = uploadUrlResponse as? HTTPURLResponse else {
            print("❌ [AttachmentService] Invalid response type")
            throw AttachmentError.uploadFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: uploadUrlData, encoding: .utf8) {
                print("❌ [AttachmentService] Failed to get upload URL: \(httpResponse.statusCode)")
                print("❌ [AttachmentService] Response: \(responseString)")
            }
            throw AttachmentError.uploadFailed
        }

        // Parse upload URL response
        struct UploadUrlResponse: Codable {
            let uploadUrl: String
            let pathname: String
            let headers: [String: String]
            let oldBlobUrl: String?
        }

        let decoder = JSONDecoder()
        let uploadUrlInfo = try decoder.decode(UploadUrlResponse.self, from: uploadUrlData)

        print("📤 [AttachmentService] Got upload URL: \(uploadUrlInfo.uploadUrl)")
        uploadProgress = 0.2

        // Step 2: Upload directly to Vercel Blob
        print("📤 [AttachmentService] Step 2: Uploading to Vercel Blob...")
        guard let blobUrl = URL(string: uploadUrlInfo.uploadUrl) else {
            print("❌ [AttachmentService] Invalid blob URL")
            throw AttachmentError.uploadFailed
        }

        var blobRequest = URLRequest(url: blobUrl)
        blobRequest.httpMethod = "PUT"
        for (key, value) in uploadUrlInfo.headers {
            blobRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (blobData, blobResponse) = try await URLSession.shared.upload(for: blobRequest, from: newFileData)

        guard let blobHttpResponse = blobResponse as? HTTPURLResponse else {
            print("❌ [AttachmentService] Invalid blob response type")
            throw AttachmentError.uploadFailed
        }

        print("📡 [AttachmentService] Blob upload status: \(blobHttpResponse.statusCode)")

        guard (200...299).contains(blobHttpResponse.statusCode) else {
            if let responseString = String(data: blobData, encoding: .utf8) {
                print("❌ [AttachmentService] Blob upload failed: \(blobHttpResponse.statusCode)")
                print("❌ [AttachmentService] Response: \(responseString)")
            }
            throw AttachmentError.uploadFailed
        }

        // Parse blob response to get the final URL
        struct BlobUploadResponse: Codable {
            let url: String
            let pathname: String
        }

        let blobResult = try decoder.decode(BlobUploadResponse.self, from: blobData)
        print("📤 [AttachmentService] Blob URL: \(blobResult.url)")
        uploadProgress = 0.8

        // Step 3: Confirm upload with our server
        print("📤 [AttachmentService] Step 3: Confirming upload...")
        let confirmEndpoint = URL(string: Constants.API.baseURL + "/api/secure-files/\(fileId)/confirm-upload")!
        var confirmRequest = URLRequest(url: confirmEndpoint)
        confirmRequest.httpMethod = "POST"
        confirmRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        confirmRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        confirmRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "blobUrl": blobResult.url,
            "mimeType": mimeType,
            "fileSize": newFileData.count,
            "oldBlobUrl": uploadUrlInfo.oldBlobUrl ?? ""
        ])

        let (confirmData, confirmResponse) = try await URLSession.shared.data(for: confirmRequest)

        guard let confirmHttpResponse = confirmResponse as? HTTPURLResponse else {
            print("❌ [AttachmentService] Invalid confirm response type")
            throw AttachmentError.uploadFailed
        }

        guard (200...299).contains(confirmHttpResponse.statusCode) else {
            if let responseString = String(data: confirmData, encoding: .utf8) {
                print("❌ [AttachmentService] Confirm failed: \(confirmHttpResponse.statusCode)")
                print("❌ [AttachmentService] Response: \(responseString)")
            }
            throw AttachmentError.uploadFailed
        }

        // Parse confirm response
        struct ConfirmResponse: Codable {
            let id: String
            let originalName: String
            let mimeType: String
            let fileSize: Int
            let updatedAt: String
            let success: Bool
        }

        let confirmResult = try decoder.decode(ConfirmResponse.self, from: confirmData)

        // Invalidate cached download for this file
        invalidateCache(for: fileId)

        print("✅ [AttachmentService] File updated: \(fileId)")
        uploadProgress = 1.0

        // Notify that file was updated
        NotificationCenter.default.post(
            name: .attachmentUpdated,
            object: nil,
            userInfo: ["fileId": fileId]
        )

        return SecureFile(
            id: confirmResult.id,
            name: confirmResult.originalName,
            size: confirmResult.fileSize,
            mimeType: confirmResult.mimeType
        )
    }

    /// Invalidate cached data for a file (used after updates)
    func invalidateCache(for fileId: String) {
        let cachedPath = downloadCacheDirectory.appendingPathComponent(fileId)
        try? fileManager.removeItem(at: cachedPath)
        print("🗑️ [AttachmentService] Invalidated cache for: \(fileId)")
    }

    // MARK: - Delete

    func deleteAttachment(taskId: String, attachmentId: String) async throws {
        let url = URL(string: Constants.API.baseURL + "/api/tasks/\(taskId)/attachments/\(attachmentId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }
    
    // MARK: - Shared Files (from Share Extension)

    /// Upload file from shared container (created by Share Extension)
    /// Used by main app to process files shared via system share sheet
    func uploadSharedFile(fileURL: URL, fileName: String, mimeType: String, taskId: String) async throws -> Attachment {
        print("📤 [AttachmentService] Uploading shared file: \(fileName)")

        // Read file data from shared container
        let fileData = try Data(contentsOf: fileURL)

        // Upload using standard method
        let attachment = try await uploadAttachment(
            taskId: taskId,
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType
        )

        // Clean up shared file after successful upload
        try? ShareDataManager.shared.deleteSharedFile(at: fileURL)
        print("✅ [AttachmentService] Shared file uploaded and cleaned up")

        return attachment
    }

    // MARK: - Helpers

    func getMimeType(for fileExtension: String) -> String {
        if let type = UTType(filenameExtension: fileExtension) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}

enum AttachmentError: LocalizedError {
    case invalidURL
    case uploadFailed
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid attachment URL"
        case .uploadFailed:
            return "Failed to upload attachment"
        case .downloadFailed:
            return "Failed to download attachment"
        }
    }
}

// MARK: - Upload Progress Delegate

/// Delegate for tracking upload progress
class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(progress)
    }
}
