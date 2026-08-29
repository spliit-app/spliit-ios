import Foundation
import SpliitAPI
import Testing

@testable import SpliitCore

@Suite("Reading a receipt")
struct ReceiptTextTests {

    /// A till receipt of the shape most of them have: a name, an address, the items, and the
    /// subtotal / tax / total triple at the bottom that is the whole reason the total is not
    /// simply "the last number".
    private let receipt = """
        CAFÉ DU COIN
        12 rue de la Paix
        75002 Paris
        01 42 61 00 00

        14/03/2025  13:42

        Café                 3,50
        Croissant            2,40
        Sandwich             8,60
        SOUS-TOTAL          14,50
        TVA 10%              1,45
        TOTAL               15,95
        CARTE               15,95
        """

    @Test("The total is the total, not the subtotal or the tax")
    func findsTheTotal() {
        #expect(ReceiptText.read(receipt).total == Decimal(string: "15.95"))
    }

    @Test("The merchant is the line above the address")
    func findsTheMerchant() {
        #expect(ReceiptText.read(receipt).title == "Café Du Coin")
    }

    @Test("The date is the one printed on it")
    func findsTheDate() throws {
        let today = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2025, month: 3, day: 20)
            )
        )
        let date = try #require(ReceiptText.read(receipt, today: today).date)
        let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2025)
        #expect(parts.month == 3)
        #expect(parts.day == 14)
    }

    /// The date detector reads a card expiry or a copyright line as happily as a purchase date,
    /// and an expense silently filed in 1999 is worse than one filed today.
    @Test("A date far outside the plausible window is ignored")
    func ignoresImplausibleDates() throws {
        let today = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2025, month: 3, day: 20)
            )
        )
        #expect(ReceiptText.date(in: "© 1999 Some Company", today: today) == nil)
        #expect(ReceiptText.date(in: "Valid until 12/2038", today: today) == nil)
    }

    @Test("Nothing readable is nothing found, not a wrong answer")
    func readsNothingFromNothing() {
        #expect(ReceiptText.read("").isEmpty)
        #expect(ReceiptText.read("¬¬¬ ### ¬¬¬").isEmpty)
    }

    // MARK: - Numbers

    /// Which separator is the decimal point is decided by the receipt, not by the phone: a
    /// French bill read on an American phone still comes to 15.95.
    @Test(
        "A number is read the way it was printed",
        arguments: [
            ("15,95", "15.95", true),
            ("15.95", "15.95", true),
            ("1 234,56", "1234.56", true),
            ("1,234.56", "1234.56", true),
            ("1.234,56", "1234.56", true),
            ("1'234.50", "1234.50", true),
            ("12", "12", false),
            ("1,234", "1234", false),
            ("1.000.000", "1000000", false),
            ("3,5", "3.5", false),
        ]
    )
    func readsNumbers(printed: String, expected: String, hasCents: Bool) {
        let amount = ReceiptText.amount(printed)
        #expect(amount?.value == Decimal(string: expected))
        #expect(amount?.hasCents == hasCents)
    }

    @Test("A line gives up every number on it, in order")
    func readsEveryNumberOnALine() {
        #expect(
            ReceiptText.amounts(in: "TOTAL 3 items    15,95").map(\.value)
                == [3, Decimal(string: "15.95")]
        )
        #expect(ReceiptText.amounts(in: "12 rue de la Paix").map(\.value) == [12])
        #expect(ReceiptText.amounts(in: "no numbers here").isEmpty)
    }

    /// Subtotal, tax and discount are all smaller than the total they belong to, which is what
    /// makes taking the largest candidate safer than any list of words could be.
    @Test("The largest of the lines that name a total wins")
    func prefersTheLargestNamedTotal() {
        let lines = ["TOTAL TAX      1.45", "TOTAL (incl. tax)   15.95", "CASH   20.00"]
        #expect(ReceiptText.total(in: lines) == Decimal(string: "15.95"))
    }

    /// Nearly every receipt outside the United States prints its VAT rate, and a 20 read off
    /// "TVA 20%" outbids the two-euro tax line it belongs to — and, on a small bill, the total.
    @Test("A percentage is not an amount")
    func ignoresPercentages() {
        #expect(ReceiptText.amounts(in: "TVA 20%   1,45").map(\.value) == [Decimal(string: "1.45")])
        #expect(ReceiptText.amounts(in: "Service 12,5 %").isEmpty)
        #expect(ReceiptText.total(in: ["TOTAL TVA 20%  1,45", "TOTAL  8,70"])
            == Decimal(string: "8.70"))
    }

    /// A keyword of one word has to match a whole word. Both of these were real hazards: a
    /// bureau de change is not a change line, and a great many bars are called something Border.
    @Test("A keyword matches a word, not a fragment of one")
    func matchesWholeWords() {
        #expect(ReceiptText.total(in: ["TOTAL EXCHANGE  15,95"]) == Decimal(string: "15.95"))
        #expect(ReceiptText.merchant(in: ["Border Cafe"]) == "Border Cafe")
    }

    @Test("A receipt that names no total falls back to its largest price")
    func fallsBackToTheLargestPrice() {
        // 75002 is a postcode and 12 is a house number: neither was printed with cents, and
        // neither is a candidate.
        let lines = ["Chez Nous", "12 rue de la Paix", "75002 Paris", "Café 3,50", "Repas 24,00"]
        #expect(ReceiptText.total(in: lines) == Decimal(string: "24.00"))
    }

    @Test("An English receipt reads the same as a French one")
    func readsEnglish() {
        let scan = ReceiptText.read(
            """
            THE CORNER PUB
            42 Long Street

            Subtotal        $18.00
            Sales Tax        $1.62
            Amount Due      $19.62
            """
        )
        #expect(scan.total == Decimal(string: "19.62"))
        #expect(scan.title == "The Corner Pub")
    }

    // MARK: - The merchant line

    @Test("Till furniture is not the name of the shop")
    func skipsHeadings() {
        #expect(ReceiptText.merchant(in: ["*** CUSTOMER COPY ***", "Chez Nous"]) == "Chez Nous")
        #expect(ReceiptText.merchant(in: ["TAX INVOICE", "MARKET HALL"]) == "Market Hall")
        #expect(ReceiptText.merchant(in: ["www.shop.example", "Shop"]) == "Shop")
        #expect(ReceiptText.merchant(in: ["1234567890", "Shop"]) == "Shop")
    }

    /// "eBay" is not "Ebay". A name printed with any lower case at all is a name someone chose
    /// how to write.
    @Test("A name that isn’t shouted is left alone")
    func keepsDeliberateCasing() {
        #expect(ReceiptText.merchant(in: ["eBay"]) == "eBay")
        #expect(ReceiptText.merchant(in: ["CAFE ROSE"]) == "Cafe Rose")
    }
}

@Suite("Putting a receipt’s rows back together")
struct ReceiptRowTests {

    /// Recorded from what `RecognizeDocumentsRequest` actually returned for the sample receipt
    /// the UI suite scans — not invented, because the point of this is the shape real document
    /// recognition produces. It reads a receipt as a page, so the labels come back as one column
    /// and the prices as another, and the last three rows arrive nine lines apart from their own
    /// numbers.
    private let blocks = [
        ("CAFE DU COIN", 0.0492, 0.9229, 0.0417),
        ("12 rue de la Paix", 0.0515, 0.8531, 0.0438),
        ("75002 Paris", 0.0515, 0.7844, 0.0438),
        ("2026-08-26", 0.0515, 0.6438, 0.0417),
        ("Cafe", 0.0489, 0.5033, 0.0417),
        ("3,50", 0.5948, 0.4974, 0.0604),
        ("Croissant", 0.0514, 0.4360, 0.0458),
        ("2,40", 0.5949, 0.4273, 0.0583),
        ("Sandwich", 0.0515, 0.3656, 0.0438),
        ("8,60", 0.5928, 0.3573, 0.0604),
        ("SOUS-TOTAL", 0.0515, 0.2250, 0.0375),
        ("TVA 10%", 0.0491, 0.1556, 0.0396),
        ("TOTAL", 0.0492, 0.0856, 0.0417),
        ("14,50", 0.5591, 0.2191, 0.0583),
        ("1,45", 0.5947, 0.1488, 0.0583),
        ("15,95", 0.5592, 0.0784, 0.0604),
    ].map { ReceiptText.Block(text: $0.0, minX: $0.1, midY: $0.2, height: $0.3) }

    @Test("A price ends up on the same row as its label")
    func rebuildsRows() {
        #expect(
            ReceiptText.rows(of: blocks) == """
                CAFE DU COIN
                12 rue de la Paix
                75002 Paris
                2026-08-26
                Cafe   3,50
                Croissant   2,40
                Sandwich   8,60
                SOUS-TOTAL   14,50
                TVA 10%   1,45
                TOTAL   15,95
                """
        )
    }

    /// The whole reason the rows are rebuilt. Read as the document reader hands them over, no
    /// line carries both the word "TOTAL" and a number, so the reading falls through to "the
    /// largest price on the receipt" — which is right on the sample above only by luck, and
    /// wrong the moment the receipt also records what was handed over.
    ///
    /// The two `CASH` runs are the one thing here not recorded from Vision: they are added by
    /// hand, on the blank row above the subtotal, to put the failure mode in front of the test.
    @Test("Rebuilding the rows is what makes the total the total")
    func readsTheTotalFromTheRowThatNamesIt() {
        let tendered = [
            ReceiptText.Block(text: "CASH", minX: 0.0515, midY: 0.2950, height: 0.0400),
            ReceiptText.Block(text: "20,00", minX: 0.5590, midY: 0.2890, height: 0.0580),
        ]
        #expect(
            ReceiptText.read(ReceiptText.rows(of: blocks + tendered)).total
                == Decimal(string: "15.95")
        )
        #expect(
            ReceiptText.read((blocks + tendered).map(\.text).joined(separator: "\n")).total
                == Decimal(string: "20.00")
        )
    }
}

@Suite("Guessing a receipt’s category")
struct ReceiptCategoriesTests {

    private let categories = [
        ExpenseCategory(id: 1, grouping: "Uncategorized", name: "General"),
        ExpenseCategory(id: 12, grouping: "Food and Drink", name: "Dining Out"),
        ExpenseCategory(id: 13, grouping: "Food and Drink", name: "Groceries"),
        ExpenseCategory(id: 40, grouping: "Transportation", name: "Taxi"),
    ]

    @Test("A category is matched by either half of its name, however it is cased")
    func matchesByName() {
        #expect(ReceiptCategories.match("Dining Out", in: categories) == 12)
        #expect(ReceiptCategories.match("Food and Drink/Dining Out", in: categories) == 12)
        #expect(ReceiptCategories.match("dining out", in: categories) == 12)
    }

    /// The model is told the vocabulary but not made to obey it, so an invented category has to
    /// come back as nobody's rather than as somebody's.
    @Test("A category nobody has is nobody’s")
    func refusesUnknownNames() {
        #expect(ReceiptCategories.match("Spaceship Fuel", in: categories) == nil)
        #expect(ReceiptCategories.match("", in: categories) == nil)
        #expect(ReceiptCategories.match(nil, in: categories) == nil)
    }

    @Test("The shop’s own name is what the category is guessed from")
    func guessesFromTheMerchant() {
        #expect(ReceiptText.read("CAFÉ DU COIN\n12 rue\nTOTAL 4,00", categories: categories)
            .categoryID == 12)
        #expect(ReceiptText.read("SUPERMARCHÉ EXPRESS\nTOTAL 40,00", categories: categories)
            .categoryID == 13)
        #expect(ReceiptText.read("TAXI PARISIEN\nTOTAL 22,00", categories: categories)
            .categoryID == 40)
    }

    /// A supermarket bill has "wine" and "coffee" printed all over it, and the shop it came from
    /// is what the category is about.
    @Test("The item list is not read for the category")
    func ignoresTheItems() {
        let scan = ReceiptText.read(
            "MARKET HALL\n15 High Street\n\nCoffee 3.00\nPizza 8.00\nTOTAL 11.00",
            categories: categories
        )
        #expect(scan.categoryID == nil)
    }

    @Test("A category this server doesn’t have is left unset")
    func leavesUnknownCategoriesAlone() {
        let withoutFood = [ExpenseCategory(id: 1, grouping: "Uncategorized", name: "General")]
        #expect(ReceiptText.read("CAFÉ DU COIN\nTOTAL 4,00", categories: withoutFood)
            .categoryID == nil)
    }
}

@Suite("Applying a receipt to the expense form")
struct ReceiptApplyTests {

    private let group = Group(
        id: "g1",
        name: "Trip",
        information: nil,
        currency: "$",
        currencyCode: "USD",
        createdAt: .now,
        participants: [Participant(id: "p1", name: "Ana"), Participant(id: "p2", name: "Bruno")]
    )

    private func draft(locale: Locale = Locale(identifier: "en_US")) -> ExpenseFormDraft {
        ExpenseFormDraft(creatingIn: group, locale: locale)
    }

    @Test("What the receipt gave up is filled in")
    func fillsTheForm() throws {
        var form = draft()
        let date = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2025, month: 3, day: 14)
            )
        )
        form.apply(
            ReceiptScan(title: "Café Du Coin", total: Decimal(string: "15.95"), date: date, categoryID: 12)
        )

        #expect(form.title == "Café Du Coin")
        #expect(form.amountText == "15.95")
        #expect(form.amountMinorUnits == 1595)
        #expect(form.expenseDate == date)
        #expect(form.categoryID == 12)
    }

    @Test("What it didn’t find is left as it was")
    func leavesTheRestAlone() {
        var form = draft()
        form.title = "Dinner"
        form.amountText = "20.00"
        form.apply(ReceiptScan())

        #expect(form.title == "Dinner")
        #expect(form.amountText == "20.00")
    }

    /// A yen group keeps no minor units at all, so 1595 on the receipt is ¥1,595 and dividing by
    /// a hundred anywhere in here would be wrong by two orders of magnitude.
    @Test("The total is scaled by the currency the group counts in")
    func scalesByTheGroupCurrency() {
        let yen = Group(
            id: "g2", name: "Tokyo", information: nil, currency: "¥", currencyCode: "JPY",
            createdAt: .now, participants: [Participant(id: "p1", name: "Ana")]
        )
        var form = ExpenseFormDraft(creatingIn: yen, locale: Locale(identifier: "en_US"))
        form.apply(ReceiptScan(total: 1595))

        #expect(form.amountText == "1595")
        #expect(form.amountMinorUnits == 1595)
    }

    /// The receipt is in the currency it was paid in, which under a conversion is not the
    /// group's — so the total belongs in the amount *paid*, and the group's total goes on being
    /// derived from it at the rate.
    @Test("Under a conversion the total is what was paid, in the currency of the receipt")
    func fillsTheAmountPaidWhenConverting() {
        var form = draft()
        form.useCurrency("EUR")
        form.use(rate: Decimal(string: "1.10")!)
        form.apply(ReceiptScan(total: Decimal(string: "40.00")))

        #expect(form.originalAmountText == "40.00")
        #expect(form.amountText.isEmpty)
        #expect(form.amountMinorUnits == 4400)
    }

    @Test("A form written in a comma locale gets a comma")
    func writesTheAmountInTheUserLocale() {
        var form = draft(locale: Locale(identifier: "fr_FR"))
        form.apply(ReceiptScan(total: Decimal(string: "15.95")))

        #expect(form.amountText == "15,95")
        #expect(form.amountMinorUnits == 1595)
    }
}
