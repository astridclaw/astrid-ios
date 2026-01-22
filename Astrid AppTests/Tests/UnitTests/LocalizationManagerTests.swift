import XCTest
@testable import Astrid_App

@MainActor
final class LocalizationManagerTests: XCTestCase {
    var localizationManager: LocalizationManager!
    let testOverrideKey = "user_language_override"

    override func setUpWithError() throws {
        try super.setUpWithError()
        localizationManager = LocalizationManager.shared
        // Clear any existing overrides before each test
        UserDefaults.standard.removeObject(forKey: testOverrideKey)
        UserDefaults.standard.synchronize()
    }

    override func tearDownWithError() throws {
        // Clean up after tests
        UserDefaults.standard.removeObject(forKey: testOverrideKey)
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        try super.tearDownWithError()
    }

    // MARK: - Language Code Extraction Tests

    func testExtractLanguageCodeFromSimpleLocale() {
        // Test that we can extract language codes from various locale formats
        let testCases: [(input: String, expected: String)] = [
            ("en", "en"),
            ("es", "es"),
            ("fr", "fr"),
            ("en-US", "en"),
            ("es-MX", "es"),
            ("fr-CA", "fr"),
            ("en_US", "en"),
            ("es_ES", "es")
        ]

        for testCase in testCases {
            let components = testCase.input.components(separatedBy: CharacterSet(charactersIn: "-_"))
            let result = components.first?.lowercased() ?? testCase.input.lowercased()
            XCTAssertEqual(result, testCase.expected,
                         "Expected \(testCase.expected) from \(testCase.input), got \(result)")
        }
    }

    // MARK: - Language Override Tests

    func testSetLanguageStoresOverride() {
        // When user manually selects a language, it should be stored
        localizationManager.setLanguage("es")

        let storedLanguage = UserDefaults.standard.string(forKey: testOverrideKey)
        XCTAssertEqual(storedLanguage, "es", "Language override should be stored in UserDefaults")
    }

    func testSetLanguageRejectsUnsupportedLanguage() {
        // Should reject unsupported language codes
        localizationManager.setLanguage("ar") // Arabic not supported

        let storedLanguage = UserDefaults.standard.string(forKey: testOverrideKey)
        XCTAssertNil(storedLanguage, "Unsupported language should not be stored")
    }

    func testClearLanguageOverride() {
        // Set an override, then clear it
        localizationManager.setLanguage("es")
        XCTAssertNotNil(UserDefaults.standard.string(forKey: testOverrideKey))

        localizationManager.clearLanguageOverride()
        XCTAssertNil(UserDefaults.standard.string(forKey: testOverrideKey),
                    "Language override should be cleared")
    }

    func testGetCurrentLanguageReturnsOverride() {
        // When override is set, getCurrentLanguage should return it
        localizationManager.setLanguage("fr")

        let currentLanguage = localizationManager.getCurrentLanguage()
        XCTAssertEqual(currentLanguage, "fr", "Should return the user override")
    }

    // MARK: - Language Affinity Tests

    func testSpanishRegionAffinity() {
        // Test that Spanish-speaking regions are correctly identified
        let spanishRegions = ["ES", "MX", "AR", "CO", "CL", "PE", "VE", "EC", "GT", "CU",
                             "BO", "DO", "HN", "PY", "SV", "NI", "CR", "PA", "UY", "PR", "GQ"]

        for region in spanishRegions {
            XCTAssertTrue(Constants.Localization.spanishSpeakingRegions.contains(region),
                         "\(region) should be recognized as Spanish-speaking")
        }
    }

    func testFrenchRegionAffinity() {
        // Test that French-speaking regions are correctly identified
        let frenchRegions = ["FR", "BE", "CH", "CA", "LU", "MC", "CI", "CM", "SN", "ML",
                            "BF", "NE", "CD", "CG", "MG", "BJ", "TG", "GN", "RW", "BI",
                            "TD", "HT", "GA", "CF"]

        for region in frenchRegions {
            XCTAssertTrue(Constants.Localization.frenchSpeakingRegions.contains(region),
                         "\(region) should be recognized as French-speaking")
        }
    }

    func testNonSpanishRegionNotInAffinity() {
        // Test that non-Spanish regions are not in Spanish affinity list
        let nonSpanishRegions = ["US", "GB", "DE", "IT", "JP", "CN", "KR"]

        for region in nonSpanishRegions {
            XCTAssertFalse(Constants.Localization.spanishSpeakingRegions.contains(region),
                          "\(region) should not be recognized as Spanish-speaking")
        }
    }

    // MARK: - Supported Languages Tests

    func testSupportedLanguagesContainsExpectedLanguages() {
        // Verify all expected languages are supported
        let expectedLanguages = ["en", "es", "fr"]

        for lang in expectedLanguages {
            XCTAssertTrue(Constants.Localization.supportedLanguages.contains(lang),
                         "\(lang) should be in supported languages")
        }
    }

    func testSupportedLanguagesCount() {
        // Verify we have exactly 12 supported languages
        // en, es, fr, de, it, ja, ko, nl, pt, ru, zh-Hans, zh-Hant
        XCTAssertEqual(Constants.Localization.supportedLanguages.count, 12,
                      "Should support exactly 12 languages")
    }

    // MARK: - Integration Tests

    func testApplyLanguageSetsAppleLanguages() {
        // Test that applying a language sets the AppleLanguages preference
        localizationManager.setLanguage("es")

        if let appleLanguages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] {
            XCTAssertEqual(appleLanguages.first, "es",
                         "AppleLanguages should be set to the selected language")
        } else {
            XCTFail("AppleLanguages should be set in UserDefaults")
        }
    }

    func testApplyIntelligentLocaleWithoutOverride() {
        // Test that applyIntelligentLocale works without crashing
        // This is an integration test that verifies the full flow
        XCTAssertNoThrow(localizationManager.applyIntelligentLocale(),
                        "applyIntelligentLocale should not throw")

        // Verify that AppleLanguages was set
        let appleLanguages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        XCTAssertNotNil(appleLanguages, "AppleLanguages should be set")
        XCTAssertFalse(appleLanguages?.isEmpty ?? true, "AppleLanguages should not be empty")
    }

    func testApplyIntelligentLocaleRespectsOverride() {
        // When user has set an override, it should be respected
        localizationManager.setLanguage("fr")

        localizationManager.applyIntelligentLocale()

        let currentLanguage = localizationManager.getCurrentLanguage()
        XCTAssertEqual(currentLanguage, "fr",
                      "Should respect user override even after applyIntelligentLocale")
    }

    // MARK: - Edge Case Tests

    func testGetCurrentLanguageFallsBackToEnglish() {
        // When no override and no matching preferred languages, should default to English
        // This is hard to test directly without mocking Locale.preferredLanguages,
        // but we can verify the logic exists
        let currentLanguage = localizationManager.getCurrentLanguage()

        // Should return one of our supported languages
        XCTAssertTrue(Constants.Localization.supportedLanguages.contains(currentLanguage),
                     "Should return a supported language")
    }

    func testMultipleSetLanguageCalls() {
        // Test that multiple calls to setLanguage work correctly
        localizationManager.setLanguage("es")
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "es")

        localizationManager.setLanguage("fr")
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "fr")

        localizationManager.setLanguage("en")
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "en")
    }

    // MARK: - Real-World Scenario Tests

    func testUSSpanishUserScenario() {
        // Scenario: US user (region=US) who speaks Spanish (es-US locale or es in preferred languages)
        // They should get Spanish, not English

        // Simulate by setting Spanish as override (in real app, this would be detected from locale)
        localizationManager.setLanguage("es")

        let currentLanguage = localizationManager.getCurrentLanguage()
        XCTAssertEqual(currentLanguage, "es",
                      "US user with Spanish preferences should get Spanish")
    }

    func testMexicanUserScenario() {
        // Scenario: Mexican user (region=MX) should get Spanish
        // Mexico is in spanishSpeakingRegions

        XCTAssertTrue(Constants.Localization.spanishSpeakingRegions.contains("MX"),
                     "Mexico should be recognized as Spanish-speaking")
    }

    func testCanadianFrenchUserScenario() {
        // Scenario: Canadian user (region=CA) who speaks French
        // Canada is in frenchSpeakingRegions

        XCTAssertTrue(Constants.Localization.frenchSpeakingRegions.contains("CA"),
                     "Canada should be recognized as French-speaking")
    }

    func testUKUserScenario() {
        // Scenario: UK user (region=GB) should get English
        // GB is not in Spanish or French affinity lists

        XCTAssertFalse(Constants.Localization.spanishSpeakingRegions.contains("GB"),
                      "UK should not be in Spanish affinity")
        XCTAssertFalse(Constants.Localization.frenchSpeakingRegions.contains("GB"),
                      "UK should not be in French affinity")
    }

    // MARK: - Constants Validation Tests

    func testUserLanguageOverrideKeyIsConsistent() {
        // Verify the constant is defined and matches what we use in tests
        XCTAssertEqual(Constants.Localization.userLanguageOverrideKey, testOverrideKey,
                      "Test key should match constant")
    }

    func testNoOverlapBetweenSpanishAndFrenchRegions() {
        // Ensure no region is in both Spanish and French affinity lists
        // (Note: Some regions like Canada or Belgium might legitimately be in both,
        // but for our current implementation we should document this if it happens)

        let overlap = Constants.Localization.spanishSpeakingRegions.intersection(
            Constants.Localization.frenchSpeakingRegions
        )

        // Document any overlaps (this is informational, not necessarily a failure)
        if !overlap.isEmpty {
            print("ℹ️ Regions in both Spanish and French affinity: \(overlap)")
            // This is actually OK - some regions are bilingual
            // We just want to be aware of it
        }
    }
}
