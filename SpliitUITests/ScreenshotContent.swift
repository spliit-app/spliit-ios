import Foundation

/// The group the App Store screenshots are taken of, written out once per language.
///
/// Translated rather than reused: a French screenshot showing an English group is a screenshot
/// of an app that was localised badly, and the listing is the first thing anyone sees. These are
/// the only strings in the repo that exist purely to be photographed, which is why they live
/// beside the test that takes the picture instead of in the string catalogue — nothing in the
/// app ever displays them.
struct ScreenshotContent {

    struct GroupSpec {
        let name: String
        /// Kept at the top of the home screen, and kept out of the way at the bottom. One of
        /// each, so the picture of the list shows all three of its sections.
        let isStarred: Bool
        let isArchived: Bool
        let participants: [String]
        let information: String?
        let currency: String
        let currencyCode: String
        let expenses: [ExpenseSpec]

        init(
            name: String,
            isStarred: Bool = false,
            isArchived: Bool = false,
            participants: [String],
            information: String? = nil,
            currency: String = "€",
            currencyCode: String = "EUR",
            expenses: [ExpenseSpec] = []
        ) {
            self.name = name
            self.isStarred = isStarred
            self.isArchived = isArchived
            self.participants = participants
            self.information = information
            self.currency = currency
            self.currencyCode = currencyCode
            self.expenses = expenses
        }
    }

    struct ExpenseSpec {
        let title: String
        /// Minor units in the group's currency — `4250` is €42.50, and would be ¥4,250 in a
        /// group denominated in yen.
        let amount: Int
        let paidBy: String
        /// Server category ID, from `categories.list`. What it buys is the glyph on the row.
        let category: Int
        /// How far back to date it, which is what puts the list into more than one date bucket.
        let daysAgo: Int
        var splitMode: String = "EVENLY"
        /// Per-participant share, in the units that split mode stores: a raw minor-unit amount
        /// for `BY_AMOUNT`, the share value ×100 for everything else.
        var shares: [String: Int]?
        var notes: String?
    }

    /// The group every screen after the home screen is taken of.
    let hero: GroupSpec
    /// The rest of the home screen. They are never opened, so they need no expenses.
    let others: [GroupSpec]
    /// The expense the split screenshot opens. Divided unevenly, which is the thing that screen
    /// is there to show.
    let showcaseExpense: String

    var groups: [GroupSpec] { [hero] + others }

    /// The language a run is capturing.
    ///
    /// `-testLanguage` reaches this process as the preferred language, and the environment
    /// variable is the escape hatch for a run driven some other way. Anything that isn't French
    /// gets the English set, so an unlocalised language still produces a usable listing rather
    /// than failing.
    static func forCurrentLanguage() -> ScreenshotContent {
        let language = ProcessInfo.processInfo.environment["SPLIIT_SCREENSHOT_LANGUAGE"]
            ?? Locale.preferredLanguages.first
            ?? "en"
        return language.hasPrefix("fr") ? .french : .english
    }

    // MARK: - English

    static let english = ScreenshotContent(
        hero: GroupSpec(
            name: "Weekend in Lisbon",
            isStarred: true,
            participants: ["Ana", "Bruno", "Chloé", "Dan"],
            information: """
                Flat is on Rua do Século, keys in the lockbox — code 4417. \
                Everything goes in here, we settle up before the flight home.
                """,
            expenses: [
                ExpenseSpec(
                    title: "Museum tickets", amount: 3600, paidBy: "Chloé",
                    category: 2, daysAgo: 0
                ),
                ExpenseSpec(
                    title: "Dinner at Ramiro", amount: 12680, paidBy: "Ana",
                    category: 8, daysAgo: 1
                ),
                ExpenseSpec(
                    title: "Tram tickets", amount: 2400, paidBy: "Dan",
                    category: 29, daysAgo: 2
                ),
                ExpenseSpec(
                    title: "Airbnb in Alfama", amount: 48000, paidBy: "Ana",
                    category: 32, daysAgo: 5,
                    splitMode: "BY_AMOUNT",
                    shares: ["Ana": 15000, "Bruno": 11000, "Chloé": 11000, "Dan": 11000],
                    notes: "Two nights, cleaning fee included. Ana took the double room."
                ),
                ExpenseSpec(
                    title: "Fado show tickets", amount: 8800, paidBy: "Bruno",
                    category: 5, daysAgo: 6
                ),
                ExpenseSpec(
                    title: "Market groceries", amount: 5630, paidBy: "Bruno",
                    category: 9, daysAgo: 11
                ),
                ExpenseSpec(
                    title: "Ferry to Cacilhas", amount: 1560, paidBy: "Chloé",
                    category: 27, daysAgo: 15
                ),
                ExpenseSpec(
                    title: "Airport taxi", amount: 4250, paidBy: "Dan",
                    category: 35, daysAgo: 38
                ),
                ExpenseSpec(
                    title: "Pharmacy run", amount: 1870, paidBy: "Chloé",
                    category: 25, daysAgo: 41
                ),
            ]
        ),
        others: [
            GroupSpec(
                name: "Flat 3B",
                participants: ["Ana", "Bruno", "Priya"],
                currency: "£", currencyCode: "GBP"
            ),
            GroupSpec(
                name: "Ski trip",
                participants: ["Chloé", "Dan", "Ana", "Bruno", "Priya"]
            ),
            GroupSpec(
                name: "Office lunches",
                participants: ["Ana", "Bruno", "Priya", "Dan", "Marc", "Chloé"]
            ),
            GroupSpec(
                name: "Barcelona 2025",
                isArchived: true,
                participants: ["Ana", "Bruno", "Chloé", "Dan"]
            ),
        ],
        showcaseExpense: "Airbnb in Alfama"
    )

    // MARK: - French

    static let french = ScreenshotContent(
        hero: GroupSpec(
            name: "Week-end à Lisbonne",
            isStarred: true,
            participants: ["Anaïs", "Baptiste", "Chloé", "Malik"],
            information: """
                L’appartement est rue do Século, les clés sont dans la boîte — code 4417. \
                On note tout ici et on solde avant le vol du retour.
                """,
            expenses: [
                ExpenseSpec(
                    title: "Billets de musée", amount: 3600, paidBy: "Chloé",
                    category: 2, daysAgo: 0
                ),
                ExpenseSpec(
                    title: "Dîner chez Ramiro", amount: 12680, paidBy: "Anaïs",
                    category: 8, daysAgo: 1
                ),
                ExpenseSpec(
                    title: "Billets de tramway", amount: 2400, paidBy: "Malik",
                    category: 29, daysAgo: 2
                ),
                ExpenseSpec(
                    title: "Airbnb à Alfama", amount: 48000, paidBy: "Anaïs",
                    category: 32, daysAgo: 5,
                    splitMode: "BY_AMOUNT",
                    shares: ["Anaïs": 15000, "Baptiste": 11000, "Chloé": 11000, "Malik": 11000],
                    notes: "Deux nuits, ménage compris. Anaïs a pris la chambre double."
                ),
                ExpenseSpec(
                    title: "Billets pour le fado", amount: 8800, paidBy: "Baptiste",
                    category: 5, daysAgo: 6
                ),
                ExpenseSpec(
                    title: "Courses au marché", amount: 5630, paidBy: "Baptiste",
                    category: 9, daysAgo: 11
                ),
                ExpenseSpec(
                    title: "Ferry pour Cacilhas", amount: 1560, paidBy: "Chloé",
                    category: 27, daysAgo: 15
                ),
                ExpenseSpec(
                    title: "Taxi depuis l’aéroport", amount: 4250, paidBy: "Malik",
                    category: 35, daysAgo: 38
                ),
                ExpenseSpec(
                    title: "Passage à la pharmacie", amount: 1870, paidBy: "Chloé",
                    category: 25, daysAgo: 41
                ),
            ]
        ),
        others: [
            GroupSpec(
                name: "Colocation 3B",
                participants: ["Anaïs", "Baptiste", "Priya"]
            ),
            GroupSpec(
                name: "Séjour au ski",
                participants: ["Chloé", "Malik", "Anaïs", "Baptiste", "Priya"]
            ),
            GroupSpec(
                name: "Déjeuners du bureau",
                participants: ["Anaïs", "Baptiste", "Priya", "Malik", "Marc", "Chloé"]
            ),
            GroupSpec(
                name: "Barcelone 2025",
                isArchived: true,
                participants: ["Anaïs", "Baptiste", "Chloé", "Malik"]
            ),
        ],
        showcaseExpense: "Airbnb à Alfama"
    )
}
