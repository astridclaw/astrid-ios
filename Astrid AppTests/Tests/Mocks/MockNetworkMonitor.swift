import Foundation
import Combine
@testable import Astrid_App

/// Mock NetworkMonitor for simulating offline/online conditions in tests
@MainActor
class MockNetworkMonitor {
    static let shared = MockNetworkMonitor()

    @Published var isConnected = true
    @Published var connectionType: ConnectionType = .wifi

    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }

    /// Factory method for tests - creates a fresh instance
    static func createForTesting() -> MockNetworkMonitor {
        let instance = MockNetworkMonitor()
        instance.reset()
        return instance
    }

    init() {}

    /// Simulate going offline
    func simulateOffline() {
        isConnected = false
        connectionType = .unknown
        NotificationCenter.default.post(name: .networkDidBecomeUnavailable, object: nil)
        print("🧪 [MockNetworkMonitor] Simulated offline state")
    }

    /// Simulate going online
    func simulateOnline(type: ConnectionType = .wifi) {
        isConnected = true
        connectionType = type
        NotificationCenter.default.post(name: .networkDidBecomeAvailable, object: nil)
        print("🧪 [MockNetworkMonitor] Simulated online state (\(type))")
    }

    /// Simulate connection restoration after being offline
    func simulateConnectionRestoration() {
        simulateOnline()
    }

    /// Reset to default online state
    func reset() {
        isConnected = true
        connectionType = .wifi
    }
}
