import Foundation
import SpliitAPI

/// How a group's expenses are usually divided, remembered so the next one starts there.
///
/// A couple splitting 70/30 was retyping that on every expense — and, worse, an expense where
/// they forgot to leave `.evenly` was silently wrong rather than refused. This is the web app's
/// "save as default splitting options" in local form: the same thing remembered, per group, on
/// whichever device is asked.
///
/// It does not travel to the server. The flag the web app sends alongside an expense is read by
/// its own browser and by nothing else — the tRPC procedures never see the split anyone wants to
/// keep — so a default set here is one this app remembers, and one set in a browser stays there.
public struct DefaultSplit: Codable, Sendable, Hashable {

    public var splitMode: SplitMode

    /// Everyone in the remembered split, and what each was given, on the ×100 scale the protocol
    /// uses for share counts and percentages alike.
    ///
    /// Who is in it matters as much as the numbers: a group of five where two of them always
    /// share the taxi remembers those two, whatever the mode.
    ///
    /// Nil for `.byAmount`, whose shares are one expense's own amounts — the €12.40 somebody
    /// owed on Tuesday's receipt means nothing on Wednesday's. Only the mode is worth keeping,
    /// and the web app keeps only the mode there too.
    public var shares: [String: Int]?

    public init(splitMode: SplitMode, shares: [String: Int]? = nil) {
        self.splitMode = splitMode
        self.shares = shares
    }

    /// What to remember from an expense that has just been saved.
    ///
    /// Built from the payload rather than from the form, because these numbers have been
    /// through validation: every share is parsed, positive, and — under the modes that require
    /// it — adds up. A draft still being typed in has none of that.
    ///
    /// An even split of the whole group is kept as the *group*, with no shares at all. Those
    /// hundreds say nothing under `.evenly` beyond who was in it, and "everybody" is the one
    /// answer that should still be right after somebody moves in: written down as two names, a
    /// third flatmate would be left out of every expense from then on, silently, and it is real
    /// money. Under the other modes the numbers do mean something and cannot be handed to
    /// somebody who was never given any — nobody can join 50/30/20 without breaking it — so
    /// those keep their names and leave the newcomer out until an expense says otherwise.
    public init(remembering values: ExpenseFormValues, participants: [Participant]) {
        let paidFor = Set(values.paidFor.map(\.participant))
        let isOnlyMembership =
            values.splitMode == .evenly && paidFor == Set(participants.map(\.id))

        self.init(
            splitMode: values.splitMode,
            shares: values.splitMode == .byAmount || isOnlyMembership
                ? nil
                : values.paidFor.reduce(into: [:]) { $0[$1.participant] = $1.shares }
        )
    }

    /// Whether this still describes a split of `participants`.
    ///
    /// Somebody remembered who has since left the group makes the whole of it stale rather than
    /// smaller: the shares that are left no longer add up to what anyone agreed — 70/30 without
    /// the 30 is not "70", it is a percentage split that cannot be saved — and quietly dropping a
    /// name is how a default becomes a split nobody chose. The web app discards it for the same
    /// reason. A new participant is not a problem: they were never in it.
    public func applies(to participants: [Participant]) -> Bool {
        guard let shares else { return true }
        let present = Set(participants.map(\.id))
        return shares.keys.allSatisfy(present.contains)
    }
}
