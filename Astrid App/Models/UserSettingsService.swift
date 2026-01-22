import Foundation
import Combine

/// User settings synced across devices
struct UserSettings: Codable {
    var smartTaskCreationEnabled: Bool?
    var emailToTaskEnabled: Bool?
    var defaultTaskDueOffset: String?
    var defaultDueTime: String?

    init(
        smartTaskCreationEnabled: Bool? = true,
        emailToTaskEnabled: Bool? = true,
        defaultTaskDueOffset: String? = "1_week",
        defaultDueTime: String? = "17:00"
    ) {
        self.smartTaskCreationEnabled = smartTaskCreationEnabled
        self.emailToTaskEnabled = emailToTaskEnabled
        self.defaultTaskDueOffset = defaultTaskDueOffset
        self.defaultDueTime = defaultDueTime
    }
}

/// Service for managing user settings with server sync
@MainActor
class UserSettingsService: ObservableObject {
    static let shared = UserSettingsService()

    @Published var settings: UserSettings
    private var updateTask: _Concurrency.Task<Void, Never>?

    private let userDefaultsKey = "user_settings"

    private init() {
        // Load from UserDefaults first (offline support)
        if let savedData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedSettings = try? JSONDecoder().decode(UserSettings.self, from: savedData) {
            self.settings = savedSettings
            print("✅ [UserSettings] Loaded from UserDefaults")
        } else {
            // Start with default settings
            self.settings = UserSettings()
            print("ℹ️ [UserSettings] Using default settings")
        }

        // Load from server in background
        _Concurrency.Task {
            await fetchSettings()
        }

        // Register for SSE updates from other devices
        _Concurrency.Task { [weak self] in
            guard let self = self else { return }
            await SSEClient.shared.onUserSettingsUpdated { settings in
                _Concurrency.Task { @MainActor [weak self] in
                    self?.handleSSEUpdate(settings)
                }
            }
        }
    }

    /// Convenience accessor for smart task creation
    var smartTaskCreationEnabled: Bool {
        get { settings.smartTaskCreationEnabled ?? true }
        set { updateSettings(UserSettings(smartTaskCreationEnabled: newValue)) }
    }

    /// Fetch settings from server
    func fetchSettings() async {
        do {
            guard let url = URL(string: "\(Constants.API.baseURL)/api/user/settings") else {
                print("❌ Invalid URL for user settings")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Add session cookie if available
            if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            } else {
                print("⚠️ No session cookie available for user settings")
                return
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response for user settings")
                return
            }

            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                let fetchedSettings = try decoder.decode(UserSettings.self, from: data)
                self.settings = fetchedSettings

                // Save to UserDefaults for offline support
                if let encoded = try? JSONEncoder().encode(fetchedSettings) {
                    UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
                    print("✅ [UserSettings] Loaded from server and saved to UserDefaults")
                }
            } else {
                print("❌ Failed to fetch user settings: \(httpResponse.statusCode)")
            }
        } catch {
            print("❌ Error fetching user settings: \(error)")
        }
    }

    /// Update settings on server
    func updateSettings(_ updates: UserSettings) {
        // Cancel any pending update
        updateTask?.cancel()

        // Merge updates into current settings
        var merged = self.settings
        if let smartTaskCreation = updates.smartTaskCreationEnabled {
            merged.smartTaskCreationEnabled = smartTaskCreation
        }
        if let emailToTask = updates.emailToTaskEnabled {
            merged.emailToTaskEnabled = emailToTask
        }
        if let dueOffset = updates.defaultTaskDueOffset {
            merged.defaultTaskDueOffset = dueOffset
        }
        if let dueTime = updates.defaultDueTime {
            merged.defaultDueTime = dueTime
        }

        // Optimistically update local state
        self.settings = merged

        // Save to UserDefaults immediately for offline support
        if let encoded = try? JSONEncoder().encode(merged) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💾 [UserSettings] Saved to UserDefaults")
        }

        // Debounce server update (300ms)
        updateTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000) // 300ms

            guard !_Concurrency.Task.isCancelled else { return }

            do {
                guard let url = URL(string: "\(Constants.API.baseURL)/api/user/settings") else {
                    print("❌ Invalid URL for user settings update")
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "PATCH"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                // Add session cookie if available
                if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                    request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
                } else {
                    print("⚠️ No session cookie available for user settings update")
                    return
                }

                let encoder = JSONEncoder()
                request.httpBody = try encoder.encode(updates)

                let (_, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid response for user settings update")
                    return
                }

                if httpResponse.statusCode == 200 {
                    print("✅ Updated user settings on server")
                } else {
                    print("❌ Failed to update user settings: \(httpResponse.statusCode)")
                }
            } catch {
                print("❌ Error updating user settings: \(error)")
            }
        }
    }

    /// Handle SSE update from another device
    func handleSSEUpdate(_ newSettings: UserSettings) {
        print("🔔 [SSE] User settings updated from another device")
        self.settings = newSettings

        // Save to UserDefaults for offline support
        if let encoded = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💾 [UserSettings] Saved SSE update to UserDefaults")
        }
    }

    /// Clear all settings data on logout
    /// This prevents data leakage between users
    func clearData() {
        // Cancel any pending updates
        updateTask?.cancel()
        updateTask = nil

        // Reset to default settings
        settings = UserSettings()

        // Clear persisted data
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)

        print("🗑️ [UserSettings] Data cleared for logout")
    }
}
