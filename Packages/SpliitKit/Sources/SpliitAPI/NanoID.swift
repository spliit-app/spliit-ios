import Foundation

/// The IDs Spliit mints: 21 characters drawn from `A-Za-z0-9_-`, which is `nanoid()` with its
/// defaults and what the web app's `randomId()` returns for every group, participant and expense.
///
/// The client mints one itself for an expense it is about to create, so the split the form
/// previews can be seeded with the ID the expense is saved under — see `Spliit.createExpense`.
/// The server checks the shape (`/^[A-Za-z0-9_-]{21}$/`) and refuses anything else, so the
/// alphabet and the length here are a contract, not a choice.
public enum NanoID {

    static let alphabet: [Character] = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    )
    static let length = 21

    /// A fresh ID from the system's cryptographic generator — the same source `nanoid` draws
    /// from in a browser — so two phones cannot mint the same one and collide on the primary key.
    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }
}
