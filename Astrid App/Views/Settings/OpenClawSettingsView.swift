import SwiftUI

/// Authentication modes for OpenClaw gateways
/// Note: Tailscale auth is not supported because astrid.cc servers connect to gateways,
/// and they cannot be on users' private Tailscale networks.
enum OpenClawAuthMode: String, CaseIterable, Identifiable {
    case astridSigned = "astrid-signed"
    case token = "token"
    case none = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .astridSigned: return NSLocalizedString("settings.openclaw.auth_mode.astrid_signed", comment: "")
        case .token: return NSLocalizedString("settings.openclaw.auth_mode.token", comment: "")
        case .none: return NSLocalizedString("settings.openclaw.auth_mode.none", comment: "")
        }
    }

    var description: String {
        switch self {
        case .astridSigned: return NSLocalizedString("settings.openclaw.auth_mode.astrid_signed_desc", comment: "")
        case .token: return NSLocalizedString("settings.openclaw.auth_mode.token_desc", comment: "")
        case .none: return NSLocalizedString("settings.openclaw.auth_mode.none_desc", comment: "")
        }
    }

    var requiresToken: Bool {
        self == .token
    }
}

/// View for managing OpenClaw workers (self-hosted AI gateways)
struct OpenClawSettingsView: View {
    @Environment(\.colorScheme) var colorScheme

    @State private var workers: [OpenClawWorker] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var successMessage: String?

    // Add worker sheet state
    @State private var showAddWorkerSheet = false
    @State private var newWorkerName = ""
    @State private var newWorkerUrl = ""
    @State private var newWorkerAuthMode: OpenClawAuthMode = .astridSigned
    @State private var newWorkerToken = ""
    @State private var isAddingWorker = false
    @State private var addWorkerError: String?

    // Health check and delete state
    @State private var checkingHealthId: String?
    @State private var deletingId: String?

    private let apiClient = AstridAPIClient.shared

    var body: some View {
        Form {
            // Header
            headerSection

            // Messages
            if let successMessage = successMessage {
                successMessageSection(successMessage)
            }

            if let errorMessage = errorMessage {
                errorMessageSection(errorMessage)
            }

            // Workers list
            if isLoading {
                loadingSection
            } else if workers.isEmpty {
                emptyStateSection
            } else {
                workersSection
            }

            // Add worker button
            addWorkerSection

            // Info section
            infoSection

            // Security warning
            securitySection
        }
        .scrollContentBackground(.hidden)
        .themedBackgroundPrimary()
        .navigationTitle(NSLocalizedString("settings.openclaw.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddWorkerSheet) {
            addWorkerSheet
        }
        .task {
            await loadWorkers()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                HStack {
                    Text("🦞")
                        .font(.title2)
                    Text(NSLocalizedString("settings.openclaw.title", comment: ""))
                        .font(Theme.Typography.headline())
                }

                Text(NSLocalizedString("settings.openclaw.description", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }
        }
    }

    // MARK: - Messages

    private func successMessageSection(_ message: String) -> some View {
        Section {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(message)
                    .font(Theme.Typography.body())
                    .foregroundColor(.green)
            }
        }
    }

    private func errorMessageSection(_ message: String) -> some View {
        Section {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(Theme.Typography.body())
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        Section {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(NSLocalizedString("settings.openclaw.loading", comment: ""))
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        Section {
            VStack(alignment: .center, spacing: Theme.spacing12) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                Text(NSLocalizedString("settings.openclaw.no_workers", comment: ""))
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Text(NSLocalizedString("settings.openclaw.no_workers_hint", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacing16)
        }
    }

    // MARK: - Workers List

    private var workersSection: some View {
        Section(header: Text(NSLocalizedString("settings.openclaw.workers_section", comment: ""))) {
            ForEach(workers) { worker in
                workerRow(worker)
            }
        }
    }

    private func workerRow(_ worker: OpenClawWorker) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            // Name and status
            HStack {
                Text(worker.name)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Spacer()

                statusBadge(for: worker.status)
            }

            // Gateway URL
            Text(worker.gatewayUrl)
                .font(Theme.Typography.caption1())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            // Auth mode and last seen
            HStack {
                Text(authModeDisplayName(worker.authMode))
                    .font(Theme.Typography.caption2())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                if let lastSeen = worker.lastSeen {
                    Text("•")
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    Text(formatDate(lastSeen))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }

                Spacer()
            }

            // Error message if any
            if let error = worker.lastError, !error.isEmpty {
                Text(error)
                    .font(Theme.Typography.caption2())
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            // Actions
            HStack(spacing: Theme.spacing16) {
                // Check health button
                Button(action: { _Concurrency.Task { await checkHealth(workerId: worker.id) } }) {
                    HStack(spacing: 4) {
                        if checkingHealthId == worker.id {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "heart.text.square")
                        }
                        Text(NSLocalizedString("settings.openclaw.check_health", comment: ""))
                    }
                    .font(Theme.Typography.caption1())
                }
                .disabled(checkingHealthId != nil || deletingId != nil)

                Spacer()

                // Delete button
                Button(role: .destructive, action: { _Concurrency.Task { await deleteWorker(workerId: worker.id) } }) {
                    HStack(spacing: 4) {
                        if deletingId == worker.id {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text(NSLocalizedString("settings.openclaw.delete_worker", comment: ""))
                    }
                    .font(Theme.Typography.caption1())
                }
                .disabled(checkingHealthId != nil || deletingId != nil)
            }
            .padding(.top, Theme.spacing4)
        }
        .padding(.vertical, Theme.spacing4)
    }

    private func statusBadge(for status: String) -> some View {
        let (color, text) = statusInfo(for: status)
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(Theme.Typography.caption2())
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    private func statusInfo(for status: String) -> (Color, String) {
        switch status {
        case "online":
            return (.green, NSLocalizedString("settings.openclaw.status.online", comment: ""))
        case "offline":
            return (.gray, NSLocalizedString("settings.openclaw.status.offline", comment: ""))
        case "error":
            return (.red, NSLocalizedString("settings.openclaw.status.error", comment: ""))
        case "busy":
            return (.orange, NSLocalizedString("settings.openclaw.status.busy", comment: ""))
        default:
            return (.gray, NSLocalizedString("settings.openclaw.status.unknown", comment: ""))
        }
    }

    private func authModeDisplayName(_ mode: String) -> String {
        OpenClawAuthMode(rawValue: mode)?.displayName ?? mode
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Add Worker Section

    private var addWorkerSection: some View {
        Section {
            Button(action: {
                resetAddWorkerForm()
                showAddWorkerSheet = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Theme.accent)
                    Text(NSLocalizedString("settings.openclaw.add_worker", comment: ""))
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    // MARK: - Add Worker Sheet

    private var addWorkerSheet: some View {
        NavigationStack {
            Form {
                // Worker name
                Section(header: Text(NSLocalizedString("settings.openclaw.worker_name", comment: ""))) {
                    TextField(
                        NSLocalizedString("settings.openclaw.worker_name_placeholder", comment: ""),
                        text: $newWorkerName
                    )
                    .autocorrectionDisabled()
                }

                // Gateway URL
                Section(
                    header: Text(NSLocalizedString("settings.openclaw.gateway_url", comment: "")),
                    footer: Text(NSLocalizedString("settings.openclaw.gateway_url_hint", comment: ""))
                ) {
                    TextField(
                        NSLocalizedString("settings.openclaw.gateway_url_placeholder", comment: ""),
                        text: $newWorkerUrl
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                }

                // Auth mode
                Section(header: Text(NSLocalizedString("settings.openclaw.auth_mode", comment: ""))) {
                    Picker(NSLocalizedString("settings.openclaw.auth_mode", comment: ""), selection: $newWorkerAuthMode) {
                        ForEach(OpenClawAuthMode.allCases) { mode in
                            VStack(alignment: .leading) {
                                Text(mode.displayName)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(newWorkerAuthMode.description)
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }

                // Auth token (only for token mode)
                if newWorkerAuthMode.requiresToken {
                    Section(header: Text(NSLocalizedString("settings.openclaw.auth_token", comment: ""))) {
                        SecureField(
                            NSLocalizedString("settings.openclaw.auth_token_placeholder", comment: ""),
                            text: $newWorkerToken
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    }
                }

                // Error message
                if let error = addWorkerError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(Theme.Typography.body())
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("settings.openclaw.add_worker", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        showAddWorkerSheet = false
                    }
                    .disabled(isAddingWorker)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAddingWorker {
                        ProgressView()
                    } else {
                        Button(NSLocalizedString("settings.openclaw.add_worker_action", comment: "")) {
                            _Concurrency.Task { await addWorker() }
                        }
                        .disabled(!isValidWorkerInput)
                    }
                }
            }
        }
    }

    private var isValidWorkerInput: Bool {
        !newWorkerName.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidGatewayUrl(newWorkerUrl) &&
        (!newWorkerAuthMode.requiresToken || !newWorkerToken.isEmpty)
    }

    private func isValidGatewayUrl(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("ws://") || trimmed.hasPrefix("wss://")
    }

    private func resetAddWorkerForm() {
        newWorkerName = ""
        newWorkerUrl = ""
        newWorkerAuthMode = .astridSigned
        newWorkerToken = ""
        addWorkerError = nil
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(NSLocalizedString("settings.openclaw.about", comment: ""))
                    .font(Theme.Typography.subheadline())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Text(NSLocalizedString("settings.openclaw.about_description", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                Text("openclaw@astrid.cc")
                    .font(Theme.Typography.caption1())
                    .foregroundColor(Theme.accent)
            }
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                HStack {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("settings.openclaw.security_title", comment: ""))
                        .font(Theme.Typography.subheadline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                }

                Text(NSLocalizedString("settings.openclaw.security_warning", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }
        }
    }

    // MARK: - API Actions

    private func loadWorkers() async {
        isLoading = true
        errorMessage = nil

        do {
            workers = try await apiClient.getOpenClawWorkers()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func addWorker() async {
        isAddingWorker = true
        addWorkerError = nil

        do {
            let response = try await apiClient.createOpenClawWorker(
                name: newWorkerName.trimmingCharacters(in: .whitespaces),
                gatewayUrl: newWorkerUrl.trimmingCharacters(in: .whitespaces),
                authToken: newWorkerAuthMode.requiresToken ? newWorkerToken : nil,
                authMode: newWorkerAuthMode.rawValue
            )

            workers.insert(response.worker, at: 0)
            showAddWorkerSheet = false

            if let test = response.connectionTest {
                if test.success {
                    successMessage = NSLocalizedString("settings.openclaw.worker_added_success", comment: "")
                } else {
                    successMessage = NSLocalizedString("settings.openclaw.worker_added_warning", comment: "")
                }
            } else {
                successMessage = NSLocalizedString("settings.openclaw.worker_added", comment: "")
            }

            // Clear success message after delay
            _Concurrency.Task {
                try? await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { successMessage = nil }
            }
        } catch {
            addWorkerError = error.localizedDescription
        }

        isAddingWorker = false
    }

    private func checkHealth(workerId: String) async {
        checkingHealthId = workerId
        errorMessage = nil

        do {
            let health = try await apiClient.checkOpenClawWorkerHealth(id: workerId)

            // Update worker in list
            if let index = workers.firstIndex(where: { $0.id == workerId }) {
                // Create updated worker with new status
                let oldWorker = workers[index]
                let updatedWorker = OpenClawWorker(
                    id: oldWorker.id,
                    name: oldWorker.name,
                    gatewayUrl: oldWorker.gatewayUrl,
                    authMode: oldWorker.authMode,
                    status: health.status,
                    lastSeen: ISO8601DateFormatter().date(from: health.lastSeen ?? ""),
                    lastError: health.health.error,
                    isActive: oldWorker.isActive,
                    createdAt: oldWorker.createdAt,
                    updatedAt: Date()
                )
                workers[index] = updatedWorker
            }

            if health.health.success {
                successMessage = NSLocalizedString("settings.openclaw.health_ok", comment: "")
            } else {
                errorMessage = health.health.error ?? NSLocalizedString("settings.openclaw.health_failed", comment: "")
            }

            // Clear messages after delay
            _Concurrency.Task {
                try? await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    successMessage = nil
                    if health.health.success {
                        errorMessage = nil
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        checkingHealthId = nil
    }

    private func deleteWorker(workerId: String) async {
        deletingId = workerId
        errorMessage = nil

        do {
            try await apiClient.deleteOpenClawWorker(id: workerId)
            workers.removeAll { $0.id == workerId }
            successMessage = NSLocalizedString("settings.openclaw.worker_deleted", comment: "")

            // Clear success message after delay
            _Concurrency.Task {
                try? await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { successMessage = nil }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        deletingId = nil
    }
}

#Preview {
    NavigationStack {
        OpenClawSettingsView()
    }
}
