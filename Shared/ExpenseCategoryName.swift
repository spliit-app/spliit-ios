import Foundation

/// What a category is called, in the user's language.
///
/// The server has no notion of locale here: `categories.list` returns "Groceries" and
/// "Nourriture et boissons" to everyone alike. The web app translates them on the client from
/// its `messages/*.json`, and this is the same table — keyed the same way `ExpenseCategoryIcon`
/// is keyed, `"<grouping>/<name>"`, so the glyph and the word can never drift apart.
///
/// The catalogue keys are the English names themselves, in a `Categories` table of their own:
/// they are a vocabulary the server owns rather than words this app wrote, and keeping them
/// apart means a category can never accidentally share an entry — and a translation — with a
/// button that happens to read the same.
///
/// A category this build has never heard of returns nil, and the caller shows whatever the
/// server sent. Spliit instances can be self-hosted and the category table is seeded data, so a
/// name arriving from the future is a thing that happens; showing it in English beats showing a
/// blank where a category should be.
enum ExpenseCategoryName {

    /// The heading a group of categories sits under in the picker.
    static func heading(_ grouping: String) -> String? {
        switch grouping {
        case "Uncategorized": String(localized: "Uncategorized", table: "Categories")
        case "Entertainment": String(localized: "Entertainment", table: "Categories")
        case "Food and Drink": String(localized: "Food and Drink", table: "Categories")
        case "Home": String(localized: "Home", table: "Categories")
        case "Life": String(localized: "Life", table: "Categories")
        case "Transportation": String(localized: "Transportation", table: "Categories")
        case "Utilities": String(localized: "Utilities", table: "Categories")
        default: nil
        }
    }

    /// One category's own name. Several contain a slash of their own ("Bus/Train", "Heat/Gas"),
    /// which is why the key is concatenated rather than split — the same reason the icon map
    /// gives.
    static func name(grouping: String, name: String) -> String? {
        switch "\(grouping)/\(name)" {
        case "Uncategorized/General": String(localized: "General", table: "Categories")
        case "Uncategorized/Payment": String(localized: "Payment", table: "Categories")

        case "Entertainment/Entertainment": String(localized: "Entertainment", table: "Categories")
        case "Entertainment/Games": String(localized: "Games", table: "Categories")
        case "Entertainment/Movies": String(localized: "Movies", table: "Categories")
        case "Entertainment/Music": String(localized: "Music", table: "Categories")
        case "Entertainment/Sports": String(localized: "Sports", table: "Categories")

        case "Food and Drink/Food and Drink": String(localized: "Food and Drink", table: "Categories")
        case "Food and Drink/Dining Out": String(localized: "Dining Out", table: "Categories")
        case "Food and Drink/Groceries": String(localized: "Groceries", table: "Categories")
        case "Food and Drink/Liquor": String(localized: "Liquor", table: "Categories")

        case "Home/Home": String(localized: "Home", table: "Categories")
        case "Home/Electronics": String(localized: "Electronics", table: "Categories")
        case "Home/Furniture": String(localized: "Furniture", table: "Categories")
        case "Home/Household Supplies": String(localized: "Household Supplies", table: "Categories")
        case "Home/Maintenance": String(localized: "Maintenance", table: "Categories")
        case "Home/Mortgage": String(localized: "Mortgage", table: "Categories")
        case "Home/Pets": String(localized: "Pets", table: "Categories")
        case "Home/Rent": String(localized: "Rent", table: "Categories")
        case "Home/Services": String(localized: "Services", table: "Categories")

        case "Life/Childcare": String(localized: "Childcare", table: "Categories")
        case "Life/Clothing": String(localized: "Clothing", table: "Categories")
        case "Life/Donation": String(localized: "Donation", table: "Categories")
        case "Life/Education": String(localized: "Education", table: "Categories")
        case "Life/Gifts": String(localized: "Gifts", table: "Categories")
        case "Life/Insurance": String(localized: "Insurance", table: "Categories")
        case "Life/Medical Expenses": String(localized: "Medical Expenses", table: "Categories")
        case "Life/Taxes": String(localized: "Taxes", table: "Categories")

        case "Transportation/Transportation": String(localized: "Transportation", table: "Categories")
        case "Transportation/Bicycle": String(localized: "Bicycle", table: "Categories")
        case "Transportation/Bus/Train": String(localized: "Bus/Train", table: "Categories")
        case "Transportation/Car": String(localized: "Car", table: "Categories")
        case "Transportation/Gas/Fuel": String(localized: "Gas/Fuel", table: "Categories")
        case "Transportation/Hotel": String(localized: "Hotel", table: "Categories")
        case "Transportation/Parking": String(localized: "Parking", table: "Categories")
        case "Transportation/Plane": String(localized: "Plane", table: "Categories")
        case "Transportation/Taxi": String(localized: "Taxi", table: "Categories")

        case "Utilities/Utilities": String(localized: "Utilities", table: "Categories")
        case "Utilities/Cleaning": String(localized: "Cleaning", table: "Categories")
        case "Utilities/Electricity": String(localized: "Electricity", table: "Categories")
        case "Utilities/Heat/Gas": String(localized: "Heat/Gas", table: "Categories")
        case "Utilities/Trash": String(localized: "Trash", table: "Categories")
        case "Utilities/TV/Phone/Internet": String(localized: "TV/Phone/Internet", table: "Categories")
        case "Utilities/Water": String(localized: "Water", table: "Categories")

        default: nil
        }
    }
}
