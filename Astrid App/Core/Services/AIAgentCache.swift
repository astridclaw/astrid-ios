import Foundation

/// Cache for AI agents to support offline mode
/// Stores AI agents locally so they're available when the API is unreachable
final class AIAgentCache {
    static let shared = AIAgentCache()

    private let userDefaults = UserDefaults.standard
    private let cacheKey = "cached_ai_agents"
    private let cacheTimestampKey = "cached_ai_agents_timestamp"

    /// Cache duration: 1 hour (refresh frequently to pick up image/name changes)
    private let cacheDuration: TimeInterval = 1 * 60 * 60

    private init() {}

    /// Save AI agents to local cache
    func save(_ agents: [User]) {
        guard !agents.isEmpty else { return }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(agents)
            userDefaults.set(data, forKey: cacheKey)
            userDefaults.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
            print("✅ [AIAgentCache] Saved \(agents.count) AI agents to cache")
        } catch {
            print("❌ [AIAgentCache] Failed to save agents: \(error)")
        }
    }

    /// Load AI agents from local cache
    /// Returns nil if cache is empty or expired
    func load() -> [User]? {
        // Check if cache exists
        guard let data = userDefaults.data(forKey: cacheKey) else {
            // Silent return - no agents cached is normal state
            return nil
        }

        // Check if cache is expired
        let timestamp = userDefaults.double(forKey: cacheTimestampKey)
        let cacheAge = Date().timeIntervalSince1970 - timestamp
        if cacheAge > cacheDuration {
            clear()
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let agents = try decoder.decode([User].self, from: data)
            return agents
        } catch {
            print("❌ [AIAgentCache] Failed to load agents: \(error)")
            clear()
            return nil
        }
    }

    /// Clear the cache
    func clear() {
        userDefaults.removeObject(forKey: cacheKey)
        userDefaults.removeObject(forKey: cacheTimestampKey)
        // Silent clear - this is routine maintenance
    }
}
