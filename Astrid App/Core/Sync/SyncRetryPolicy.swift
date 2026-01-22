import Foundation

/// Retry policy with exponential backoff for sync operations
struct SyncRetryPolicy: Codable {
    var attempt: Int = 0
    var lastAttemptAt: Date?
    var lastError: String?

    /// Maximum retry attempts before giving up
    static let maxAttempts = 10

    /// Calculate next retry delay using exponential backoff (1s → 2s → 4s → ... → 32s max)
    var nextRetryDelay: TimeInterval {
        let baseDelay: TimeInterval = 1
        let maxDelay: TimeInterval = 32
        return min(baseDelay * pow(2, Double(attempt)), maxDelay)
    }

    /// Whether we should give up on this operation
    var shouldGiveUp: Bool {
        attempt >= Self.maxAttempts
    }

    /// Whether we can retry now (respects backoff delay)
    var canRetryNow: Bool {
        guard !shouldGiveUp else { return false }
        guard let lastAttempt = lastAttemptAt else { return true }
        return Date().timeIntervalSince(lastAttempt) >= nextRetryDelay
    }

    /// Record a failed attempt
    mutating func recordFailure(error: String) {
        attempt += 1
        lastAttemptAt = Date()
        lastError = error
    }

    /// Reset after successful sync
    mutating func reset() {
        attempt = 0
        lastAttemptAt = nil
        lastError = nil
    }
}

/// Sync operation priority levels
enum SyncPriority: Int, Comparable, Codable {
    case critical = 0  // Task completion - user intent
    case high = 1      // Task create
    case normal = 2    // Task updates
    case low = 3       // Attachments, non-critical

    static func < (lhs: SyncPriority, rhs: SyncPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Entity types for sync tracking
enum SyncEntityType: String, Codable {
    case task
    case comment
    case list
    case member
    case attachment
}
