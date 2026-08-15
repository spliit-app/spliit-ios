import Foundation

/// Picks the colour and the letters for a participant's monogram.
///
/// The colour has to be stable: the same person keeps the same colour between launches, and two
/// people looking at the same group on different phones see each other the same way. Swift's own
/// `hashValue` is seeded per process, so it would reshuffle the whole palette on every launch —
/// hence the hash here rather than `Hashable`.
public enum MonogramPalette {

    /// How many colours the palette holds. The asset catalogue defines this many `Monogram<n>`
    /// colour sets, numbered from 1.
    public static let count = 8

    /// The colour for someone at a known position in a list — how **participants** are coloured.
    ///
    /// Position beats hashing here, and the difference is visible. Hashing four participants into
    /// eight buckets collides more often than not, and two people sharing a colour in the same
    /// group defeats the whole point of giving them one. Positions inside a group are distinct, so
    /// nobody collides until a group passes `count` members.
    ///
    /// The order comes from the server and is the same everywhere, so this is still the same
    /// colour on every device. It moves for everyone after a participant who is removed, which is
    /// the price of never colliding — and removing a participant is rare next to reading a
    /// balance.
    public static func index(atPosition position: Int) -> Int {
        ((position % count) + count) % count
    }

    /// The colour for something with no position to speak of — how **groups** are coloured. The
    /// home screen reorders itself as groups are opened, so a group's colour has to come from its
    /// identity rather than its row.
    ///
    /// - Parameter seed: the group's **ID**, not its name, so the colour survives a rename.
    /// - Returns: an index in `0..<count`.
    public static func index(for seed: String) -> Int {
        // FNV-1a, 64-bit: a handful of lines, no dependencies, and well spread over the short
        // opaque IDs the API hands out.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(count))
    }

    /// The one or two letters drawn inside the monogram.
    ///
    /// Empty for a nameless participant, which validation already rules out — a blank chip is a
    /// quieter failure than a placeholder glyph that looks like an error.
    public static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }
}
