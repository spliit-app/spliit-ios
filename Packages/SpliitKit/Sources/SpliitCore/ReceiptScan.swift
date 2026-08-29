import Foundation
import SpliitAPI

/// What a receipt turned out to say.
///
/// Every field is optional and independent: a photo that gives up its total but not its date is
/// worth most of what a perfect one is, and a receipt that yields nothing at all is a normal
/// outcome rather than an error. Nothing here is authoritative — it lands in a form the user is
/// about to read anyway.
public struct ReceiptScan: Equatable, Sendable {

    /// The merchant, as printed at the top.
    public var title: String?
    /// The grand total, in the currency's *major* units — 15.95, not 1595. The draft it is
    /// applied to is what knows how many digits that currency keeps.
    public var total: Decimal?
    public var date: Date?
    /// One of the group's own categories, resolved against what the server actually offers.
    public var categoryID: Int?

    public init(
        title: String? = nil,
        total: Decimal? = nil,
        date: Date? = nil,
        categoryID: Int? = nil
    ) {
        self.title = title
        self.total = total
        self.date = date
        self.categoryID = categoryID
    }

    /// Whether the scan found anything at all, which is what decides between "check this" and
    /// "that photo told us nothing".
    public var isEmpty: Bool {
        title == nil && total == nil && date == nil && categoryID == nil
    }

    /// This reading, with anything it is missing taken from `fallback`.
    ///
    /// Field by field rather than all-or-nothing: the on-device model and the text parser are
    /// good at different halves of a receipt, and the one that answered should win over the one
    /// that shrugged whichever of the two it is.
    public func completed(by fallback: ReceiptScan) -> ReceiptScan {
        ReceiptScan(
            title: title ?? fallback.title,
            total: total ?? fallback.total,
            date: date ?? fallback.date,
            categoryID: categoryID ?? fallback.categoryID
        )
    }
}

/// Reads a receipt out of the text some OCR made of it.
///
/// This is the whole of the feature on a phone with no Apple Intelligence, and the safety net
/// under the on-device model everywhere else — so it is deliberately dumb and deliberately
/// tested: no network, no model, no state, and every rule below is a rule about how receipts
/// are printed rather than about what an expense means.
///
/// The vocabulary is English and French, which are the languages the app ships. A receipt in a
/// third language still yields its total when the total is the largest amount on it, which is
/// most of the time.
public enum ReceiptText {

    /// One run of text some OCR found, and where on the page it found it.
    ///
    /// Normalised the way Vision reports coordinates: 0…1 across the image, with the origin at
    /// the bottom left. Only the vertical middle, the left edge and the height are kept, which
    /// is all that deciding what sits beside what needs.
    public struct Block: Sendable, Equatable {
        public let text: String
        public let minX: Double
        public let midY: Double
        public let height: Double

        public init(text: String, minX: Double, midY: Double, height: Double) {
            self.text = text
            self.minX = minX
            self.midY = midY
            self.height = height
        }
    }

    /// Puts a receipt's rows back together out of the runs of text OCR found.
    ///
    /// This is not a nicety. Document recognition reads a receipt the way it reads a page — as
    /// blocks in reading order — so the labels come out as one block and the prices as another,
    /// and "TOTAL" ends up several lines away from the number that was printed beside it. Every
    /// rule below about what a line says would then be reading lines that never existed.
    ///
    /// Two runs are on the same row when their vertical middles are closer together than half
    /// the height of the shorter one: a price and its label are printed on the same baseline,
    /// and the next row down is a whole line-height away.
    public static func rows(of blocks: [Block]) -> String {
        var rows: [[Block]] = []
        // Top of the page first, which is neither the order Vision returns nor the order a
        // receipt is printed in — it is the order a person reads it in.
        for block in blocks.sorted(by: { $0.midY > $1.midY }) {
            guard let last = rows.last?.first else {
                rows.append([block])
                continue
            }
            let tolerance = max(min(last.height, block.height), 0.001) / 2
            if abs(last.midY - block.midY) < tolerance {
                rows[rows.count - 1].append(block)
            } else {
                rows.append([block])
            }
        }

        return rows
            .map { row in
                row.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: "   ")
            }
            .joined(separator: "\n")
    }

    /// Everything readable, from a transcript in reading order.
    ///
    /// - Parameters:
    ///   - categories: what the server offers, so a guessed category comes back as an ID this
    ///     group can actually store. Empty leaves `categoryID` nil.
    ///   - today: the day to judge a date's plausibility against, injectable for the tests.
    public static func read(
        _ transcript: String,
        categories: [ExpenseCategory] = [],
        today: Date = .now
    ) -> ReceiptScan {
        let lines = transcript
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let title = merchant(in: lines)
        return ReceiptScan(
            title: title,
            total: total(in: lines),
            date: date(in: transcript, today: today),
            categoryID: ReceiptCategories.guess(fromMerchant: title, in: categories)
        )
    }

    // MARK: - The total

    /// Lines that name a total. Folded, so "À PAYER" and "a payer" are the same line.
    private static let totalKeywords = [
        "total", "amount due", "balance due", "grand total", "to pay",
        "montant", "a payer", "somme",
    ]

    /// Lines that name a total *of something else*. Short on purpose: the real defence is taking
    /// the largest of the candidates, since a subtotal, a tax and a discount are all smaller than
    /// the total they belong to — and unlike a keyword list, that stays true in every language.
    private static let notATotalKeywords = [
        "sous-total", "sous total", "subtotal", "sub total", "total ht", "total h.t",
        "hors taxe", "tva", "vat", "tip", "pourboire", "change", "rendu",
    ]

    static func total(in lines: [String]) -> Decimal? {
        let candidates = lines.filter { line in
            names(totalKeywords, in: line) && !names(notATotalKeywords, in: line)
        }

        if let named = candidates.flatMap({ amounts(in: $0).map(\.value) }).max() {
            return named
        }
        // Nothing named a total — a hand-written slip, or OCR that lost the word. The largest
        // amount printed with cents is the best guess there is, and a receipt's largest amount
        // is very often its total.
        return lines
            .flatMap { amounts(in: $0) }
            .filter(\.hasCents)
            .map(\.value)
            .max()
    }

    /// The first number written anywhere in a piece of text.
    ///
    /// What reads the total back out of the on-device model's answer, which is asked for as text
    /// precisely so that one piece of code parses every number this feature handles: a model that
    /// writes "$1,234.56" is read exactly as a receipt printing the same thing is.
    public static func number(in text: String) -> Decimal? {
        amounts(in: text).first?.value
    }

    /// Whether a line names one of these.
    ///
    /// A keyword of one word has to match a whole word: "change" must not find "exchange", and
    /// "order" must not find "Border Cafe". Anything with a space or a hyphen in it is matched as
    /// written, since a phrase cannot collide with a longer word.
    static func names(_ keywords: [String], in line: String) -> Bool {
        let folded = fold(line)
        let words = Set(folded.split { !$0.isLetter }.map(String.init))
        return keywords.contains { keyword in
            keyword.contains(where: { !$0.isLetter }) ? folded.contains(keyword)
                : words.contains(keyword)
        }
    }

    /// One number found on a line, and whether it was written as money.
    struct Amount: Equatable {
        var value: Decimal
        /// Exactly two digits behind a separator. A price; not a house number or a postcode.
        var hasCents: Bool
    }

    /// The separators a number can be written with, anywhere in the world: a space (in three
    /// widths), an apostrophe in Switzerland, and the two that also serve as decimal points.
    private static let groupingCharacters: Set<Character> = [
        " ", "\u{00A0}", "\u{202F}", "'", "\u{2019}",
    ]
    private static let decimalCharacters: Set<Character> = [".", ","]

    /// Every number on a line, in the order they were printed.
    ///
    /// A run of digits and separators, bounded by anything else — so "12 RUE DE LA PAIX" gives 12
    /// and "TOTAL 1 234,56" gives 1234.56 rather than 1 and 234.56.
    ///
    /// A percentage is not one of them. Nearly every receipt outside the United States prints its
    /// VAT rate, and "TVA 20%  1,45" offering up a 20 is how a two-euro tax line comes to
    /// outbid the total it was charged on.
    static func amounts(in line: String) -> [Amount] {
        var found: [Amount] = []
        var run: [Character] = []

        func finish(endedBy terminator: Character?) {
            defer { run = [] }
            guard terminator != "%" else { return }
            // A run bounded by separators rather than by digits — " 12, " — is punctuation that
            // happened to sit beside a number, and its edges are not part of it.
            while let first = run.first, !first.isNumber { run.removeFirst() }
            while let last = run.last, !last.isNumber { run.removeLast() }
            if let amount = amount(String(run)) { found.append(amount) }
        }

        for character in line {
            if character.isNumber || groupingCharacters.contains(character)
                || decimalCharacters.contains(character) {
                run.append(character)
            } else {
                finish(endedBy: character)
            }
        }
        finish(endedBy: nil)
        return found
    }

    /// One run of digits and separators, resolved into a number.
    ///
    /// Which separator is the decimal point is decided by what follows the last one rather than
    /// by the locale: a receipt is printed wherever it was printed, and a phone carried abroad
    /// would otherwise read every price on it wrong. One or two digits after the last separator
    /// makes it a decimal point; anything else makes every separator a grouping mark, so
    /// "1,234" is a thousand and not one and a bit.
    static func amount(_ run: String) -> Amount? {
        let characters = Array(run).filter { !groupingCharacters.contains($0) }
        guard characters.contains(where: \.isNumber) else { return nil }

        let digits = characters.filter(\.isNumber)
        guard let lastSeparator = characters.lastIndex(where: decimalCharacters.contains) else {
            return Decimal(string: String(digits)).map { Amount(value: $0, hasCents: false) }
        }

        let fraction = characters.count - lastSeparator - 1
        guard fraction == 1 || fraction == 2 else {
            return Decimal(string: String(digits)).map { Amount(value: $0, hasCents: false) }
        }

        let whole = characters[..<lastSeparator].filter(\.isNumber)
        let text = "\(String(whole)).\(String(characters[(lastSeparator + 1)...]))"
        return Decimal(string: text).map { Amount(value: $0, hasCents: fraction == 2) }
    }

    // MARK: - The date

    /// How far back a date on a receipt can plausibly be. Longer than anyone splits an expense
    /// over, and short enough that an OCR misreading of a card expiry or a copyright line does
    /// not silently date the expense to 1999.
    private static let plausibleAge: TimeInterval = 2 * 365 * 24 * 60 * 60

    /// Also what checks the date the on-device model answered with: a model that read a card
    /// expiry instead of the purchase date is making the same mistake the detector would, and it
    /// is caught in the same place.
    public static func date(in transcript: String, today: Date = .now) -> Date? {
        // The data detector reads far more written forms than a list of formats would, in every
        // language the phone knows — which is the point, since a receipt is printed in the
        // language of wherever it was bought.
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else { return nil }

        let range = NSRange(transcript.startIndex..., in: transcript)
        let matches = detector.matches(in: transcript, range: range)
        // Tomorrow allows for a receipt from a till whose clock is ahead, or a flight taken
        // across the date line; anything beyond that is a misreading.
        let earliest = today.addingTimeInterval(-plausibleAge)
        let latest = today.addingTimeInterval(24 * 60 * 60)

        return matches.lazy
            .compactMap(\.date)
            .first { $0 >= earliest && $0 <= latest }
    }

    // MARK: - The merchant

    /// Words a receipt heads itself with, which are never the name of the shop.
    private static let notAName = [
        "receipt", "invoice", "tax invoice", "customer copy", "merchant copy", "welcome",
        "thank you", "order", "facture", "ticket de caisse", "recu", "bienvenue", "merci",
        "duplicata",
    ]

    /// The shop's name: the first line at the top that reads like one.
    ///
    /// Receipts lead with the merchant, then the address — so the first line with more letters
    /// than digits, that isn't a URL or an email or a piece of till furniture, is it.
    static func merchant(in lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let folded = fold(line)
            let letters = line.filter(\.isLetter).count
            guard line.count <= 40, letters >= 2, letters > line.filter(\.isNumber).count,
                  !folded.contains("@"), !folded.contains("www."), !folded.contains("http"),
                  !names(notAName, in: line)
            else { continue }

            // Receipts shout. Capitalising a name that was only ever printed in capitals reads
            // as a name rather than as a heading; one that already has lower case is left as its
            // owner writes it, since "eBay" is not "Ebay".
            return line.contains(where: \.isLowercase) ? line : line.localizedCapitalized
        }
        return nil
    }

    /// Case- and accent-insensitive, so one keyword covers "TOTAL", "Total" and "À payer".
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}

/// Turning what a receipt looks like into one of the categories the server has.
///
/// The names are the server's own English vocabulary — `categories.list` answers the same words
/// to everyone — so this matches against `grouping` and `name` as they arrive rather than
/// against what the picker displays.
public enum ReceiptCategories {

    /// A category named by the on-device model, resolved against the ones that exist.
    ///
    /// Accepts either half or both: the model is told the vocabulary but not made to obey it,
    /// and "Dining Out", "Food and Drink/Dining Out" and "dining out" are all the same answer.
    /// Anything unrecognised is nobody's category rather than a wrong one.
    public static func match(_ name: String?, in categories: [ExpenseCategory]) -> Int? {
        guard let wanted = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !wanted.isEmpty
        else { return nil }

        let folded = ReceiptText.fold(wanted)
        let qualified = categories.first {
            ReceiptText.fold("\($0.grouping)/\($0.name)") == folded
        }
        return (qualified ?? categories.first { ReceiptText.fold($0.name) == folded })?.id
    }

    /// What the shop's name says about what was bought, for the phones with no model to ask.
    ///
    /// Only the merchant is read, never the items: a supermarket bill has "wine" and "coffee"
    /// printed all over it, and the shop it came from is what the category is about. A name that
    /// says nothing matches nothing, which leaves the form's own default in place.
    static func guess(fromMerchant name: String?, in categories: [ExpenseCategory]) -> Int? {
        guard let name else { return nil }
        for (category, keywords) in keywordsByCategory
        where ReceiptText.names(keywords, in: name) {
            if let id = match(category, in: categories) { return id }
        }
        return nil
    }

    /// Ordered, because the first match wins and the narrower kinds of shop have to be asked
    /// about before the broader ones — a "wine bar" is a bar.
    private static let keywordsByCategory: [(String, [String])] = [
        (
            "Food and Drink/Groceries",
            ["supermarket", "grocery", "groceries", "supermarche", "epicerie", "hypermarche"]
        ),
        (
            "Food and Drink/Liquor",
            ["liquor", "wines", "spirits", "brewery", "cave a vin", "caviste"]
        ),
        (
            "Food and Drink/Dining Out",
            [
                "restaurant", "cafe", "coffee", "bistro", "brasserie", "pizzeria", "pizza",
                "bar", "pub", "diner", "grill", "sushi", "burger", "boulangerie", "patisserie",
                "traiteur", "creperie",
            ]
        ),
        ("Transportation/Taxi", ["taxi", "cab", "vtc"]),
        ("Transportation/Hotel", ["hotel", "hostel", "auberge", "motel"]),
        ("Transportation/Parking", ["parking", "stationnement"]),
        (
            "Transportation/Gas/Fuel",
            ["fuel", "petrol", "essence", "gas station", "station service"]
        ),
        ("Entertainment/Movies", ["cinema", "cineplex", "multiplex"]),
        ("Entertainment/Entertainment", ["theatre", "museum", "musee", "concert"]),
        (
            "Life/Medical Expenses",
            ["pharmacy", "pharmacie", "clinic", "clinique", "hospital", "dentist", "dentiste"]
        ),
    ]
}

extension ExpenseFormDraft {

    /// Fills in whatever the receipt gave up, and leaves the rest of the form alone.
    ///
    /// The total lands in whichever field the expense is actually being entered in: under a
    /// currency conversion that is the amount *paid*, in the currency of the receipt, and the
    /// group's total goes on being derived from it at the rate below — see `amountMinorUnits`.
    public mutating func apply(_ scan: ReceiptScan) {
        if let title = scan.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            self.title = title
        }
        if let date = scan.date { expenseDate = date }
        if let categoryID = scan.categoryID { self.categoryID = categoryID }

        guard let total = scan.total, total > 0 else { return }
        let digits = conversionRequired ? originalMinorUnitDigits : minorUnitDigits
        let text = Self.text(
            forMinorUnits: MoneyFormatter.roundToInteger(total * pow(Decimal(10), digits)),
            locale: locale,
            minorUnitDigits: digits
        )
        if conversionRequired {
            originalAmountText = text
        } else {
            amountText = text
        }
    }
}
