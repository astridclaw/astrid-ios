import SwiftUI

/// A banner that shows the current connection mode status.
/// - Purple: Local only mode (offlineOnly)
/// - Orange: Working offline (temporary)
/// - Blue: Syncing items (online with pending operations)
struct ConnectionStatusBanner: View {
    @ObservedObject private var connectionManager = ConnectionModeManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var taskService = TaskService.shared

    @State private var isExpanded = false

    var body: some View {
        if shouldShowBanner {
            VStack(spacing: 0) {
                // Main banner
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Theme.spacing8) {
                        statusIcon
                            .frame(width: 16, height: 16)

                        statusText
                            .lineLimit(1)

                        Spacer()

                        if connectionManager.isTransitioning {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        } else if showExpandButton {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                    }
                    .font(Theme.Typography.caption1())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bannerColor)
                }
                .buttonStyle(PlainButtonStyle())

                // Expanded details
                if isExpanded && showExpandButton {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Computed Properties

    private var shouldShowBanner: Bool {
        switch connectionManager.currentMode {
        case .offlineOnly:
            return true  // Always show for offline-only mode
        case .offline:
            return true  // Show when temporarily offline
        case .online:
            // Show if syncing or has pending/failed operations
            return taskService.isSyncingPendingOperations ||
                   taskService.pendingOperationsCount > 0 ||
                   taskService.failedOperationsCount > 0
        }
    }

    private var showExpandButton: Bool {
        connectionManager.currentMode == .offlineOnly ||
        taskService.pendingOperationsCount > 0 ||
        taskService.failedOperationsCount > 0
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch connectionManager.currentMode {
        case .offlineOnly:
            Image(systemName: "iphone")
        case .offline:
            Image(systemName: "wifi.slash")
        case .online:
            if taskService.isSyncingPendingOperations {
                Image(systemName: "arrow.triangle.2.circlepath")
            } else if taskService.failedOperationsCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var statusText: Text {
        switch connectionManager.currentMode {
        case .offlineOnly:
            return Text(NSLocalizedString("status.local_only", comment: "Local only mode"))
        case .offline:
            let pending = taskService.pendingOperationsCount
            if pending > 0 {
                return Text(String(format: NSLocalizedString("status.offline_with_pending", comment: ""), pending))
            }
            return Text(NSLocalizedString("status.offline", comment: "Working offline"))
        case .online:
            if taskService.isSyncingPendingOperations {
                return Text(NSLocalizedString("status.syncing", comment: "Syncing..."))
            }
            let pending = taskService.pendingOperationsCount
            let failed = taskService.failedOperationsCount
            if failed > 0 {
                return Text(String(format: NSLocalizedString("status.sync_failed", comment: ""), failed))
            }
            if pending > 0 {
                return Text(String(format: NSLocalizedString("status.syncing_count", comment: ""), pending))
            }
            return Text(NSLocalizedString("status.synced", comment: "All synced"))
        }
    }

    private var bannerColor: Color {
        switch connectionManager.currentMode {
        case .offlineOnly:
            return .purple.opacity(0.9)
        case .offline:
            return .orange.opacity(0.9)
        case .online:
            if taskService.failedOperationsCount > 0 {
                return Theme.error.opacity(0.9)
            }
            return Theme.accent.opacity(0.9)
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            switch connectionManager.currentMode {
            case .offlineOnly:
                Text(NSLocalizedString("status.local_only_description", comment: "Your data is stored on this device only. Sign in to sync across devices."))
                    .font(Theme.Typography.caption2())

            case .offline:
                if taskService.pendingOperationsCount > 0 {
                    Text(String(format: NSLocalizedString("status.pending_sync_description", comment: ""), taskService.pendingOperationsCount))
                        .font(Theme.Typography.caption2())
                }

            case .online:
                if taskService.failedOperationsCount > 0 {
                    HStack {
                        Text(String(format: NSLocalizedString("status.failed_sync_description", comment: ""), taskService.failedOperationsCount))
                            .font(Theme.Typography.caption2())
                        Spacer()
                        Button {
                            retrySyncNow()
                        } label: {
                            Text(NSLocalizedString("status.retry_now", comment: "Retry"))
                                .font(Theme.Typography.caption1())
                                .fontWeight(.semibold)
                        }
                    }
                } else if taskService.pendingOperationsCount > 0 {
                    Text(NSLocalizedString("status.sync_in_progress", comment: "Changes will sync automatically"))
                        .font(Theme.Typography.caption2())
                }
            }
        }
        .foregroundColor(.white.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bannerColor.opacity(0.7))
    }

    // MARK: - Actions

    private func retrySyncNow() {
        _Concurrency.Task {
            try? await taskService.syncPendingOperations()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ConnectionStatusBanner()
        Spacer()
    }
}
