import Foundation
import SpliitAPI

/// What each participant's share of an expense comes to, in whole minor units.
///
/// A port of the web app's `getExpenseShares` (`src/lib/shares.ts`), which is the one definition
/// there of who owes what on an expense: the balances tab, the stats and the CSV export all go
/// through it, and so does the amount printed beside each participant in its expense form. The
/// numbers here have to be *those* numbers, to the minor unit, or the app would show a share the
/// server never charges anyone.
///
/// The shares always add up to exactly the amount, whatever the split mode. Every participant
/// gets the floor of their exact share first, and the units left over go to the largest
/// remainders — Hamilton apportionment. An even split leaves every remainder equal, so ties are
/// broken by rotating the starting position with a hash of the expense's ID: the extra cent then
/// lands on somebody different from one expense to the next, and on the same somebody every time
/// the same expense is asked about.
///
/// A server older than the web app's *Shares* change rounds each share on its own and lets the
/// sum drift, so the balances it computes for the same expense can differ from these by a minor
/// unit. That drift is what the change was made to close, and `spliit.app` runs the new one.
public enum ExpenseShares {

    /// The share per participant ID. A participant the expense was not paid for is absent.
    ///
    /// - Parameters:
    ///   - expenseId: seeds the rotation deciding who is offered the leftover minor unit of an
    ///     uneven split. For a new expense this is the ID the form minted and will send with the
    ///     create, so the preview is the split the expense is saved with — unless the instance
    ///     predates spliit#647 and mints its own, in which case the extra unit may move to
    ///     somebody else once it has. Nil starts the rotation at the first participant, as an
    ///     empty ID does in the web app.
    ///   - amount: the expense total, in the group's minor units.
    ///   - paidFor: who it was for, and their stored shares. `.byPercentage` and `.byAmount`
    ///     shares are taken as a ratio rather than literally, so a row that does not add up to
    ///     100% or to the total still divides the whole amount and nothing leaks.
    public static func shares(
        expenseId: String?,
        amount: Int,
        splitMode: SplitMode,
        paidFor: [ExpenseDetails.PaidFor]
    ) -> [String: Int] {
        // The server fetches `paidFor` without an `orderBy`, so the rows can come back in any
        // order. The web app sorts by participant ID before splitting so the result does not
        // depend on it; so does this, on the same key — UTF-16 code units, which is what a
        // JavaScript `<` compares — or the two would rotate differently.
        let rows = paidFor.sorted {
            $0.participantId.utf16.lexicographicallyPrecedes($1.participantId.utf16)
        }

        let weights: [Int] = switch splitMode {
        case .evenly: rows.map { _ in 1 }
        case .byShares, .byPercentage, .byAmount: rows.map(\.shares)
        }

        // An empty ID counts as none, as it does in JavaScript — `expense.id && …` is false
        // for "" — so the two agree on every input and not only on the ones that occur.
        let offset = expenseId.flatMap { $0.isEmpty || rows.isEmpty ? nil : $0 }
            .map { Int(fnv1a($0) % UInt32(rows.count)) } ?? 0
        let amounts = apportion(amount, weights: weights, offset: offset)

        return Dictionary(
            zip(rows.map(\.participantId), amounts),
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Splits `amount` over `weights` so that the parts add up to exactly `amount`, in the order
    /// the weights were given.
    ///
    /// - Parameter offset: where the tie-break between equal remainders starts, so an even split
    ///   does not hand the extra unit to the same participants every time.
    static func apportion(_ amount: Int, weights: [Int], offset: Int) -> [Int] {
        let count = weights.count
        guard count > 0 else { return [] }
        // Wide enough that a share count somebody typed with too many zeros adds up and
        // multiplies out rather than trapping — this runs on every keystroke in the form.
        // Shares are validated as positive on write, but a legacy or directly written row is not
        // guaranteed to be, so a total of zero is handled rather than divided by.
        let total = weights.reduce(Int128(0)) { $0 + Int128($1) }
        guard total != 0 else { return weights.map { _ in 0 } }

        var amounts: [Int] = []
        var remainders: [(index: Int, remainder: Int128)] = []
        var distributed = 0

        for (index, weight) in weights.enumerated() {
            let exact = Int128(amount) * Int128(weight)
            // Floored, not truncated, so an income — a negative amount — leaves the leftover
            // non-negative just as a spend does, and `remaining` below stays within the count.
            let base = exact.flooredDividing(by: total)
            amounts.append(Int(clamping: base))
            distributed += Int(clamping: base)
            remainders.append((index, exact - base * total))
        }

        let remaining = amount - distributed
        guard remaining > 0 else { return amounts }

        // Largest remainder first; among equals, the one nearest after `offset` going round.
        let rotate = { (index: Int) in (index - offset + count) % count }
        remainders.sort {
            $0.remainder != $1.remainder
                ? $0.remainder > $1.remainder
                : rotate($0.index) < rotate($1.index)
        }
        for slot in 0..<min(remaining, count) {
            amounts[remainders[slot].index] += 1
        }
        return amounts
    }

    /// FNV-1a, 32-bit, over UTF-16 code units — bit for bit the web app's `hashString`, which
    /// walks `charCodeAt`. Any other hash would give the leftover cent to a different person than
    /// the balances tab charges it to.
    static func fnv1a(_ value: String) -> UInt32 {
        var hash: UInt32 = 0x811c_9dc5
        for unit in value.utf16 {
            hash ^= UInt32(unit)
            hash &*= 0x0100_0193
        }
        return hash
    }
}

private extension Int128 {
    /// Division rounding toward negative infinity, like JavaScript's `Math.floor(a / b)`, where
    /// Swift's `/` rounds toward zero.
    func flooredDividing(by divisor: Int128) -> Int128 {
        let quotient = self / divisor
        let hasRemainder = self % divisor != 0
        return hasRemainder && (self < 0) != (divisor < 0) ? quotient - 1 : quotient
    }
}
