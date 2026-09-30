import Foundation
import Testing

@testable import SpliitCore

@Test("Core bundles contain French translations and retain English fallback")
func coreLocalization() throws {
    let frenchURL = try #require(Bundle.module.url(forResource: "fr", withExtension: "lproj"))
    let englishURL = try #require(Bundle.module.url(forResource: "en", withExtension: "lproj"))
    let french = try #require(Bundle(url: frenchURL))
    let english = try #require(Bundle(url: englishURL))
    #expect(NSLocalizedString("Invalid number.", bundle: french, comment: "") == "Nombre invalide.")
    #expect(NSLocalizedString("Invalid number.", bundle: english, comment: "") == "Invalid number.")
    #expect(NSLocalizedString("An untranslated message.", bundle: french, comment: "") == "An untranslated message.")
}
