import Foundation
import Combine

/// My Tasks filter preferences synced across devices
struct MyTasksPreferences: Codable {
    var filterPriority: [Int]?
    var filterAssignee: [String]?
    var filterDueDate: String?
    var filterCompletion: String?
    var sortBy: String?
    var manualSortOrder: [String]?

    init(
        filterPriority: [Int]? = [],
        filterAssignee: [String]? = [],
        filterDueDate: String? = "all",
        filterCompletion: String? = "default",
        sortBy: String? = "auto",
        manualSortOrder: [String]? = nil
    ) {
        self.filterPriority = filterPriority
        self.filterAssignee = filterAssignee
        self.filterDueDate = filterDueDate
        self.filterCompletion = filterCompletion
        self.sortBy = sortBy
        self.manualSortOrder = manualSortOrder
    }
}

/// Service for managing My Tasks preferences with server sync
@MainActor
class MyTasksPreferencesService: ObservableObject {
    static let shared = MyTasksPreferencesService()

    @Published var preferences: MyTasksPreferences
    private var updateTask: _Concurrency.Task<Void, Never>?

    private let userDefaultsKey = "my_tasks_preferences"

    private init() {
        // Load from UserDefaults first (offline support)
        if let savedData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedPrefs = try? JSONDecoder().decode(MyTasksPreferences.self, from: savedData) {
            self.preferences = savedPrefs
            print("✅ [MyTasksPrefs] Loaded from UserDefaults")
        } else {
            // Start with default preferences
            self.preferences = MyTasksPreferences()
            print("ℹ️ [MyTasksPrefs] Using default preferences")
        }

        // Load from server in background
        _Concurrency.Task {
            await fetchPreferences()
        }
    }

    /// Fetch preferences from server
    func fetchPreferences() async {
        do {
            guard let url = URL(string: "\(Constants.API.baseURL)/api/user/my-tasks-preferences") else {
                print("❌ Invalid URL for My Tasks preferences")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Add session cookie if available
            if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            } else {
                print("⚠️ No session cookie available for My Tasks preferences")
                return
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response for My Tasks preferences")
                return
            }

            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                let fetchedPrefs = try decoder.decode(MyTasksPreferences.self, from: data)
                self.preferences = fetchedPrefs

                // Save to UserDefaults for offline support
                if let encoded = try? JSONEncoder().encode(fetchedPrefs) {
                    UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
                    print("✅ [MyTasksPrefs] Loaded from server and saved to UserDefaults")
                }
            } else {
                print("❌ Failed to fetch My Tasks preferences: \(httpResponse.statusCode)")
            }
        } catch {
            print("❌ Error fetching My Tasks preferences: \(error)")
        }
    }

    /// Update preferences on server
    func updatePreferences(_ updates: MyTasksPreferences) async {
        // Cancel any pending update
        updateTask?.cancel()

        // Optimistically update local state
        self.preferences = updates

        // Save to UserDefaults immediately for offline support
        if let encoded = try? JSONEncoder().encode(updates) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💾 [MyTasksPrefs] Saved to UserDefaults")
        }

        // Debounce server update (300ms)
        updateTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000) // 300ms

            guard !_Concurrency.Task.isCancelled else { return }

            do {
                guard let url = URL(string: "\(Constants.API.baseURL)/api/user/my-tasks-preferences") else {
                    print("❌ Invalid URL for My Tasks preferences update")
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "PATCH"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                // Add session cookie if available
                if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                    request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
                } else {
                    print("⚠️ No session cookie available for My Tasks preferences update")
                    return
                }

                let encoder = JSONEncoder()
                request.httpBody = try encoder.encode(updates)

                let (_, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid response for My Tasks preferences update")
                    return
                }

                if httpResponse.statusCode == 200 {
                    print("✅ Updated My Tasks preferences on server")
                } else {
                    print("❌ Failed to update My Tasks preferences: \(httpResponse.statusCode)")
                }
            } catch {
                print("❌ Error updating My Tasks preferences: \(error)")
            }
        }
    }

    /// Handle SSE update from another device
    func handleSSEUpdate(_ newPreferences: MyTasksPreferences) {
        print("🔔 [SSE] My Tasks preferences updated from another device")
        self.preferences = newPreferences

        // Save to UserDefaults for offline support
        if let encoded = try? JSONEncoder().encode(newPreferences) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💾 [MyTasksPrefs] Saved SSE update to UserDefaults")
        }
    }

    /// Clear all preferences data on logout
    /// This prevents data leakage between users
    func clearData() {
        // Cancel any pending updates
        updateTask?.cancel()
        updateTask = nil

        // Reset to default preferences
        preferences = MyTasksPreferences()

        // Clear persisted data
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)

        print("🗑️ [MyTasksPrefs] Data cleared for logout")
    }
}
