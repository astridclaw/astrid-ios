import SwiftUI

/// Compact sync status indicator for navigation bar
struct SyncStatusView: View {
    @ObservedObject private var taskService = TaskService.shared
    @ObservedObject private var commentService = CommentService.shared
    @ObservedObject private var listMemberService = ListMemberService.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var syncManager = SyncManager.shared

    @State private var showingDetail = false

    var body: some View {
        Button(action: { showingDetail = true }) {
            statusIcon
        }
        .sheet(isPresented: $showingDetail) {
            SyncStatusDetailView()
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if syncManager.isSyncing {
            // Syncing in progress
            ProgressView()
                .scaleEffect(0.7)
        } else if !networkMonitor.isConnected {
            // Offline
            Image(systemName: "wifi.slash")
                .foregroundColor(.orange)
        } else if totalPendingCount > 0 {
            // Pending operations
            ZStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.yellow)

                // Badge with count
                Text("\(min(totalPendingCount, 99))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(3)
                    .background(Color.orange)
                    .clipShape(Circle())
                    .offset(x: 8, y: -8)
            }
        } else if totalFailedCount > 0 {
            // Failed operations
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        } else {
            // All synced
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }

    private var totalPendingCount: Int {
        taskService.pendingOperationsCount +
        commentService.pendingOperationsCount +
        listMemberService.pendingOperationsCount
    }

    private var totalFailedCount: Int {
        taskService.failedOperationsCount +
        commentService.failedOperationsCount +
        listMemberService.failedOperationsCount
    }
}

/// Detailed sync status sheet
struct SyncStatusDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var taskService = TaskService.shared
    @ObservedObject private var commentService = CommentService.shared
    @ObservedObject private var listMemberService = ListMemberService.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var syncManager = SyncManager.shared

    @State private var isRetrying = false

    var body: some View {
        NavigationView {
            List {
                // Connection status
                Section("Connection") {
                    HStack {
                        Image(systemName: networkMonitor.isConnected ? "wifi" : "wifi.slash")
                            .foregroundColor(networkMonitor.isConnected ? .green : .orange)
                        Text(networkMonitor.isConnected ? "Connected" : "Offline")
                        Spacer()
                        Text(qualityText)
                            .foregroundColor(.secondary)
                    }

                    if networkMonitor.isFlaky {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.yellow)
                            Text(NSLocalizedString("sync.unstable_connection", comment: "Unstable connection detected"))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Sync status by type
                Section("Pending Operations") {
                    SyncStatusRow(
                        title: "Tasks",
                        pending: taskService.pendingOperationsCount,
                        failed: taskService.failedOperationsCount
                    )
                    SyncStatusRow(
                        title: "Comments",
                        pending: commentService.pendingOperationsCount,
                        failed: commentService.failedOperationsCount
                    )
                    SyncStatusRow(
                        title: "Members",
                        pending: listMemberService.pendingOperationsCount,
                        failed: listMemberService.failedOperationsCount
                    )
                }

                // Actions
                if totalFailedCount > 0 {
                    Section(NSLocalizedString("actions.filter", comment: "Actions")) {
                        Button(action: retryAllFailed) {
                            HStack {
                                if isRetrying {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(NSLocalizedString("sync.retry_failed", comment: "Retry Failed Operations"))
                            }
                        }
                        .disabled(isRetrying)
                    }
                }

                // Last sync info
                if let lastSync = syncManager.lastSyncDate {
                    Section("Last Sync") {
                        Text(lastSync, style: .relative)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("sync.status", comment: "Sync Status"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var qualityText: String {
        switch networkMonitor.connectionQuality {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .unknown: return ""
        }
    }

    private var totalFailedCount: Int {
        taskService.failedOperationsCount +
        commentService.failedOperationsCount +
        listMemberService.failedOperationsCount
    }

    private func retryAllFailed() {
        isRetrying = true

        _Concurrency.Task {
            await taskService.retryFailedOperations()
            await commentService.retryFailedOperations()
            await listMemberService.retryFailedOperations()

            await MainActor.run {
                isRetrying = false
            }
        }
    }
}

/// Row showing sync status for a specific entity type
struct SyncStatusRow: View {
    let title: String
    let pending: Int
    let failed: Int

    var body: some View {
        HStack {
            Text(title)

            Spacer()

            if pending > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.yellow)
                    Text("\(pending)")
                        .foregroundColor(.secondary)
                }
            }

            if failed > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("\(failed)")
                        .foregroundColor(.secondary)
                }
            }

            if pending == 0 && failed == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
}

/// Offline mode banner
struct OfflineBanner: View {
    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        if !networkMonitor.isConnected {
            HStack {
                Image(systemName: "wifi.slash")
                Text(NSLocalizedString("sync.working_offline", comment: "Working offline"))
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange)
        }
    }
}

#Preview {
    SyncStatusView()
}
