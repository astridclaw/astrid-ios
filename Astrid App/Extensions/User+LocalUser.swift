import SwiftUI

// MARK: - User Extension for Local User Detection

extension User {
    /// Check if this user is a local-only user (not authenticated with server)
    var isLocalUser: Bool {
        id.hasPrefix("local_")
    }
}

// MARK: - AuthManager Extension for Local Mode Detection

extension AuthManager {
    /// Check if the app is in local-only mode (no server authentication)
    var isLocalOnlyMode: Bool {
        ConnectionModeManager.shared.currentMode == .offlineOnly
    }
}
