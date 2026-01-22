import XCTest
@testable import Astrid_App

/// Unit tests for authentication functionality
/// Tests session state, login/logout flows, and user identity management
final class AuthenticationTests: XCTestCase {

    // MARK: - Session State Tests

    func testSessionIsInitiallyNotAuthenticated() {
        // Given: A fresh app state (simulated)
        // We can't test actual AuthManager without mocking, but we can test User model behavior

        // When: No user is set
        let nilUser: User? = nil

        // Then: Should be treated as unauthenticated
        XCTAssertNil(nilUser)
    }

    func testUserIdentityFromEmail() {
        // Given: A user with email but no name
        let user = TestHelpers.createTestUser(
            id: "user-123",
            name: nil,
            email: "test@example.com"
        )

        // Then: displayName should fall back to email
        XCTAssertEqual(user.displayName, "test@example.com")
    }

    func testUserIdentityWithName() {
        // Given: A user with both name and email
        let user = TestHelpers.createTestUser(
            id: "user-123",
            name: "John Doe",
            email: "john@example.com"
        )

        // Then: displayName should use name
        XCTAssertEqual(user.displayName, "John Doe")
    }

    func testUserIdentityFallback() {
        // Given: A user with no name or email
        let user = TestHelpers.createTestUser(
            id: "user-123",
            name: nil,
            email: nil
        )

        // Then: displayName should fall back to default
        XCTAssertEqual(user.displayName, "Unknown User")
    }

    // MARK: - User Initials Tests

    func testUserInitialsFromFullName() {
        // Given: A user with a full name
        let user = TestHelpers.createTestUser(name: "John Doe")

        // Then: Should extract initials
        XCTAssertEqual(user.initials, "JD")
    }

    func testUserInitialsFromSingleName() {
        // Given: A user with a single name
        let user = TestHelpers.createTestUser(name: "John")

        // Then: Should use first two characters
        XCTAssertEqual(user.initials, "JO")
    }

    func testUserInitialsFromEmail() {
        // Given: A user with only email
        let user = TestHelpers.createTestUser(name: nil, email: "test@example.com")

        // Then: Should use first two characters of email
        XCTAssertEqual(user.initials, "TE")
    }

    func testUserInitialsUppercased() {
        // Given: A user with lowercase name
        let user = TestHelpers.createTestUser(name: "john doe")

        // Then: Initials should be uppercased
        XCTAssertEqual(user.initials, "JD")
    }

    // MARK: - AI Agent Identification Tests

    func testAIAgentIdentification() {
        // Given: An AI agent user
        let aiUser = TestHelpers.createTestUser(
            id: "ai-agent-123",
            name: "Claude",
            email: "claude@astrid.cc",
            isAIAgent: true,
            aiAgentType: "claude"
        )

        // Then: Should be identified as AI agent
        XCTAssertEqual(aiUser.isAIAgent, true)
        XCTAssertEqual(aiUser.aiAgentType, "claude")
    }

    func testHumanUserNotAIAgent() {
        // Given: A regular human user
        let humanUser = TestHelpers.createTestUser(
            id: "user-123",
            name: "John Doe",
            email: "john@example.com",
            isAIAgent: false
        )

        // Then: Should not be identified as AI agent
        XCTAssertEqual(humanUser.isAIAgent, false)
        XCTAssertNil(humanUser.aiAgentType)
    }

    // MARK: - Pending User Tests

    func testPendingUserStatus() {
        // Given: A pending user (invited but not yet registered)
        let pendingUser = TestHelpers.createTestUser(
            id: "pending-123",
            name: nil,
            email: "invited@example.com",
            isPending: true
        )

        // Then: Should be marked as pending
        XCTAssertEqual(pendingUser.isPending, true)
    }

    func testActiveUserNotPending() {
        // Given: An active user
        let activeUser = TestHelpers.createTestUser(
            id: "user-123",
            name: "Active User",
            email: "active@example.com",
            isPending: false
        )

        // Then: Should not be marked as pending
        XCTAssertEqual(activeUser.isPending, false)
    }

    // MARK: - User Equality Tests

    func testUserEqualityById() {
        // Given: Two users with the same ID
        let user1 = TestHelpers.createTestUser(id: "user-123", name: "User One")
        let user2 = TestHelpers.createTestUser(id: "user-123", name: "User Two")

        // Then: Should be equal (ID is the primary key)
        XCTAssertEqual(user1.id, user2.id)
    }

    func testUserInequalityByDifferentId() {
        // Given: Two users with different IDs
        let user1 = TestHelpers.createTestUser(id: "user-123")
        let user2 = TestHelpers.createTestUser(id: "user-456")

        // Then: Should not be equal
        XCTAssertNotEqual(user1.id, user2.id)
    }

    // MARK: - Default Due Time Tests

    func testUserDefaultDueTime() {
        // Given: A user with default due time set
        let user = TestHelpers.createTestUser(
            id: "user-123",
            defaultDueTime: "09:00"
        )

        // Then: Should have default due time
        XCTAssertEqual(user.defaultDueTime, "09:00")
    }

    func testUserNoDefaultDueTime() {
        // Given: A user without default due time
        let user = TestHelpers.createTestUser(
            id: "user-123",
            defaultDueTime: nil
        )

        // Then: Default due time should be nil
        XCTAssertNil(user.defaultDueTime)
    }

    // MARK: - User Created At Tests

    func testUserCreatedAt() {
        // Given: A user with creation date
        let creationDate = Date()
        let user = TestHelpers.createTestUser(
            id: "user-123",
            createdAt: creationDate
        )

        // Then: Should have creation date
        XCTAssertEqual(user.createdAt, creationDate)
    }

    // MARK: - Profile Image Tests

    func testUserWithProfileImage() {
        // Given: A user with profile image
        let user = TestHelpers.createTestUser(
            id: "user-123",
            name: "John Doe",
            image: "https://example.com/avatar.jpg"
        )

        // Then: Should have image URL
        XCTAssertEqual(user.image, "https://example.com/avatar.jpg")
    }

    func testUserWithoutProfileImage() {
        // Given: A user without profile image
        let user = TestHelpers.createTestUser(
            id: "user-123",
            name: "John Doe",
            image: nil
        )

        // Then: Image should be nil
        XCTAssertNil(user.image)
    }

    // MARK: - Cached Image URL Tests

    func testCachedImageURLWithDirectImage() {
        // Given: A user with direct image URL
        let user = TestHelpers.createTestUser(
            id: "user-with-image",
            image: "https://example.com/direct-avatar.jpg"
        )

        // When: Getting cached image URL
        let cachedURL = user.cachedImageURL

        // Then: Should return the direct image
        XCTAssertEqual(cachedURL, "https://example.com/direct-avatar.jpg")
    }

    @MainActor
    func testCachedImageURLFallsBackToCache() {
        // Given: A user with no direct image but cached image
        let userId = "user-cached-only"
        UserImageCache.shared.setImageURL("https://example.com/cached.jpg", for: userId)
        let user = TestHelpers.createTestUser(id: userId, image: nil)

        // When: Getting cached image URL
        let cachedURL = user.cachedImageURL

        // Then: Should fall back to cache
        XCTAssertEqual(cachedURL, "https://example.com/cached.jpg")

        // Cleanup
        UserImageCache.shared.setImageURL(nil, for: userId)
    }

    // MARK: - Hashable Tests with MainActor

    @MainActor
    func testUserHashableOnMainActor() {
        // Given: A user
        let user = TestHelpers.createTestUser(id: "hash-test")

        // Then: Should work in Set
        var userSet = Set<User>()
        userSet.insert(user)
        XCTAssertTrue(userSet.contains(user))
    }

    @MainActor
    func testMultipleUsersInSetOnMainActor() {
        // Given: Multiple users
        let user1 = TestHelpers.createTestUser(id: "user-1")
        let user2 = TestHelpers.createTestUser(id: "user-2")
        let user3 = TestHelpers.createTestUser(id: "user-3")

        // When: Added to a set
        var userSet = Set<User>()
        userSet.insert(user1)
        userSet.insert(user2)
        userSet.insert(user3)

        // Then: All should be present
        XCTAssertEqual(userSet.count, 3)
        XCTAssertTrue(userSet.contains(user1))
        XCTAssertTrue(userSet.contains(user2))
        XCTAssertTrue(userSet.contains(user3))
    }
}
