import Foundation
import Testing

@testable import SpliitCore

@Test("Core bundles contain French translations and retain English fallback")
func coreLocalization() throws {
    let moduleBundle = CoreResources.bundle
    let frenchURL = try #require(moduleBundle.url(forResource: "fr", withExtension: "lproj"))
    let englishURL = try #require(moduleBundle.url(forResource: "en", withExtension: "lproj"))
    #if SKIP_BRIDGE
    let frenchBundle = SpliitCore.Bundle(url: frenchURL)
    let englishBundle = SpliitCore.Bundle(url: englishURL)
    #else
    let frenchBundle = Foundation.Bundle(url: frenchURL)
    let englishBundle = Foundation.Bundle(url: englishURL)
    #endif
    let french = try #require(frenchBundle)
    let english = try #require(englishBundle)
    #expect(Foundation.NSLocalizedString("Enter at least two characters.", bundle: french, comment: "") == "Saisissez au moins deux caractères.")
    #expect(Foundation.NSLocalizedString("Invalid number.", bundle: french, comment: "") == "Nombre invalide.")
    #expect(Foundation.NSLocalizedString("Invalid number.", bundle: english, comment: "") == "Invalid number.")
    #expect(Foundation.NSLocalizedString("An untranslated message.", bundle: french, comment: "") == "An untranslated message.")
}
