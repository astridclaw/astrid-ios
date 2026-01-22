import XCTest
@testable import Astrid_App

/// Unit tests for PasskeyError enum
final class PasskeyErrorTests: XCTestCase {

    // MARK: - Error Description Tests

    func testNotSupportedError() {
        let error = PasskeyError.notSupported
        XCTAssertEqual(error.errorDescription, "Passkeys are not supported on this device")
    }

    func testUserCancelledError() {
        let error = PasskeyError.userCancelled
        XCTAssertEqual(error.errorDescription, "Passkey operation was cancelled")
    }

    func testInvalidChallengeError() {
        let error = PasskeyError.invalidChallenge
        XCTAssertEqual(error.errorDescription, "Invalid challenge from server")
    }

    func testInvalidUserIdError() {
        let error = PasskeyError.invalidUserId
        XCTAssertEqual(error.errorDescription, "Invalid user ID")
    }

    func testInvalidResponseError() {
        let error = PasskeyError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid response from authenticator")
    }

    func testAuthenticationFailedError() {
        let error = PasskeyError.authenticationFailed("Token expired")
        XCTAssertEqual(error.errorDescription, "Authentication failed: Token expired")
    }

    func testRegistrationFailedError() {
        let error = PasskeyError.registrationFailed("Server error")
        XCTAssertEqual(error.errorDescription, "Registration failed: Server error")
    }

    func testServerError() {
        let error = PasskeyError.serverError("Connection timeout")
        XCTAssertEqual(error.errorDescription, "Connection timeout")
    }

    func testUnknownError() {
        let error = PasskeyError.unknown("Something went wrong")
        XCTAssertEqual(error.errorDescription, "Unknown error: Something went wrong")
    }

    // MARK: - Existing User Error Tests

    func testExistingUserWithPasskey() {
        let error = PasskeyError.existingUser(email: "test@example.com", hasPasskey: true)
        XCTAssertEqual(
            error.errorDescription,
            "An account with this email already exists. Please sign in with your passkey."
        )
    }

    func testExistingUserWithoutPasskey() {
        let error = PasskeyError.existingUser(email: "test@example.com", hasPasskey: false)
        XCTAssertEqual(
            error.errorDescription,
            "An account with this email already exists. Please sign in with another method."
        )
    }

    // MARK: - LocalizedError Conformance Tests

    func testErrorIsLocalizedError() {
        let error: LocalizedError = PasskeyError.notSupported
        XCTAssertNotNil(error.errorDescription)
    }

    func testAllErrorsHaveDescriptions() {
        let errors: [PasskeyError] = [
            .notSupported,
            .userCancelled,
            .invalidChallenge,
            .invalidUserId,
            .invalidResponse,
            .authenticationFailed("test"),
            .registrationFailed("test"),
            .serverError("test"),
            .unknown("test"),
            .existingUser(email: "test@example.com", hasPasskey: true),
            .existingUser(email: "test@example.com", hasPasskey: false)
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error \(error) description should not be empty")
        }
    }
}
