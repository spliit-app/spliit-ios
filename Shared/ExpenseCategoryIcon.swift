import Foundation

/// The SF Symbol that stands for an expense category.
///
/// The web app maps every category to a Lucide glyph in `category-icon.tsx`. This is that map with
/// the SF Symbols equivalents, keyed the same way — `"<grouping>/<name>"` — so the two products
/// agree glyph for glyph on what a taxi or a bag of groceries looks like. Categories the server
/// adds later fall through to `banknote`, exactly as they do on the web.
///
/// It lives in `Shared/` so the test bundle compiles it too. A symbol name that does not exist
/// draws nothing at all and reports no error, so `CategoryIconTests` asks the system to resolve
/// every one of these.
enum ExpenseCategoryIcon {

    /// What the web app falls back to, and so do we.
    static let fallback = "banknote"

    static func symbol(grouping: String?, name: String?) -> String {
        guard let grouping, let name else { return fallback }
        return symbols["\(grouping)/\(name)"] ?? fallback
    }

    /// Keyed exactly as the web app keys it — note that several category *names* contain a slash
    /// of their own ("Bus/Train", "Gas/Fuel", "Heat/Gas", "TV/Phone/Internet"), which is why this
    /// is a flat string key rather than a pair.
    static let symbols: [String: String] = [
        "Uncategorized/General": "banknote",
        "Uncategorized/Payment": "banknote",

        // Lucide's ferris-wheel has no SF Symbol; a ticket carries the same idea and stays clear
        // of the glyphs used by Movies and Games.
        "Entertainment/Entertainment": "ticket",
        "Entertainment/Games": "dice",
        "Entertainment/Movies": "movieclapper",
        "Entertainment/Music": "music.note",
        "Entertainment/Sports": "dumbbell",

        "Food and Drink/Food and Drink": "fork.knife",
        "Food and Drink/Dining Out": "menucard",
        "Food and Drink/Groceries": "cart",
        "Food and Drink/Liquor": "wineglass",

        "Home/Home": "house",
        "Home/Electronics": "powerplug",
        "Home/Furniture": "chair.lounge",
        "Home/Household Supplies": "lamp.table",
        "Home/Maintenance": "wrench.adjustable",
        "Home/Mortgage": "building.columns",
        "Home/Pets": "cat",
        // Lucide uses a piggy bank; SF Symbols has none, and a key says "rent" without competing
        // with the banknote that General already owns.
        "Home/Rent": "key",
        "Home/Services": "wrench.and.screwdriver",

        "Life/Childcare": "stroller",
        "Life/Clothing": "tshirt",
        "Life/Donation": "hand.raised",
        "Life/Education": "books.vertical",
        "Life/Gifts": "gift",
        "Life/Insurance": "building.columns",
        "Life/Medical Expenses": "stethoscope",
        "Life/Taxes": "banknote",

        "Transportation/Transportation": "bus",
        "Transportation/Bicycle": "bicycle",
        "Transportation/Bus/Train": "tram",
        "Transportation/Car": "car",
        "Transportation/Gas/Fuel": "fuelpump",
        "Transportation/Hotel": "bed.double",
        "Transportation/Parking": "parkingsign",
        "Transportation/Plane": "airplane",
        "Transportation/Taxi": "car.side",

        "Utilities/Utilities": "banknote",
        "Utilities/Cleaning": "sparkles",
        "Utilities/Electricity": "bolt",
        "Utilities/Heat/Gas": "thermometer.sun",
        "Utilities/Trash": "trash",
        "Utilities/TV/Phone/Internet": "phone",
        "Utilities/Water": "drop",
    ]
}
