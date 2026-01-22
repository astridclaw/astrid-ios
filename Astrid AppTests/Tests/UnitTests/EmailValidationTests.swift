import XCTest
@testable import Astrid_App

/// Unit tests for email validation logic used in LoginView and PasskeyEmailSheet
/// Tests the validation pattern: !email.isEmpty && email.contains("@") && email.contains(".")
final class EmailValidationTests: XCTestCase {

    // Helper function matching LoginView/PasskeyEmailSheet logic
    private func isValidEmail(_ email: String) -> Bool {
        !email.isEmpty && email.contains("@") && email.contains(".")
    }

    // MARK: - Valid Email Tests

    func testValidEmailSimple() {
        XCTAssertTrue(isValidEmail("test@example.com"))
    }

    func testValidEmailWithSubdomain() {
        XCTAssertTrue(isValidEmail("user@mail.example.com"))
    }

    func testValidEmailWithPlus() {
        XCTAssertTrue(isValidEmail("test+tag@example.com"))
    }

    func testValidEmailWithNumbers() {
        XCTAssertTrue(isValidEmail("user123@example.com"))
    }

    func testValidEmailWithDots() {
        XCTAssertTrue(isValidEmail("first.last@example.com"))
    }

    func testValidEmailMinimal() {
        XCTAssertTrue(isValidEmail("a@b.c"))
    }

    // MARK: - Invalid Email Tests

    func testInvalidEmailEmpty() {
        XCTAssertFalse(isValidEmail(""))
    }

    func testInvalidEmailNoAt() {
        XCTAssertFalse(isValidEmail("testexample.com"))
    }

    func testInvalidEmailNoDot() {
        XCTAssertFalse(isValidEmail("test@examplecom"))
    }

    func testInvalidEmailNoAtNoDot() {
        XCTAssertFalse(isValidEmail("testexamplecom"))
    }

    func testInvalidEmailOnlyAt() {
        XCTAssertFalse(isValidEmail("@"))
    }

    func testInvalidEmailOnlyDot() {
        XCTAssertFalse(isValidEmail("."))
    }

    func testInvalidEmailAtOnly() {
        XCTAssertFalse(isValidEmail("test@"))
    }

    func testInvalidEmailDotOnly() {
        XCTAssertFalse(isValidEmail("test."))
    }

    func testInvalidEmailWhitespace() {
        XCTAssertFalse(isValidEmail(" "))
    }

    // MARK: - Edge Cases

    func testEmailWithMultipleAts() {
        // Our simple validation would accept this, but it's technically invalid
        // This is acceptable for basic client-side validation
        XCTAssertTrue(isValidEmail("test@@example.com"))
    }

    func testEmailWithMultipleDots() {
        XCTAssertTrue(isValidEmail("test@example.co.uk"))
    }

    func testEmailWithDotsBeforeAt() {
        XCTAssertTrue(isValidEmail("first.middle.last@example.com"))
    }

    func testEmailAtStartWithDot() {
        // Simple validation accepts this even though it's technically edge case
        XCTAssertTrue(isValidEmail(".test@example.com"))
    }

    // MARK: - Passkey Registration Context Tests

    func testPasskeyRegistrationEmailScenarios() {
        // These are realistic emails users might enter during passkey registration

        // Valid cases
        XCTAssertTrue(isValidEmail("user@gmail.com"))
        XCTAssertTrue(isValidEmail("user@icloud.com"))
        XCTAssertTrue(isValidEmail("user@outlook.com"))
        XCTAssertTrue(isValidEmail("user@company.co"))
        XCTAssertTrue(isValidEmail("firstname.lastname@company.com"))

        // Invalid cases - user is still typing
        XCTAssertFalse(isValidEmail("user"))
        XCTAssertFalse(isValidEmail("user@"))
        XCTAssertFalse(isValidEmail("user@gmail"))
    }
}
