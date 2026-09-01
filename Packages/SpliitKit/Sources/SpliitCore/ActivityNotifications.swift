import Foundation
import SpliitAPI

/// How much of a group's activity is worth interrupting somebody for.
///
/// Spliit has no accounts, and no server that has ever heard of a phone: there is nothing to
/// register a push token with and nothing to send one. So what reaches a lock screen is a
/// *local* notification this app posted after reading `groups.activities.list` for itself, in a
/// background refresh iOS granted it. That is what shapes the choice offered here — three
/// answers to "what is worth waking up for", not three subscriptions.
public enum NotificationLevel: String, Codable, Sendable, CaseIterable, Hashable {
    /// Everything the group's log records, whoever did it.
    case everything
    /// Only the expenses this person paid, or is splitting.
    case involvingMe
    case nothing

    /// The level actually applied, given whether this phone knows which participant its owner
    /// is in the group.
    ///
    /// `.involvingMe` is a filter, and a filter needs something to match against. A group whose
    /// "You" has never been answered — or was answered "Nobody" — offers nothing, so the choice
    /// is between passing everything through and dropping everything. Passing through is the
    /// recoverable mistake: an extra notification at least says the feature works, and names the
    /// group whose screen explains how to narrow it, while silence is indistinguishable from a
    /// bug. Both screens that offer this level say so in as many words, rather than leaving the
    /// widening to be discovered.
    public func resolved(knowingWhoYouAre: Bool) -> NotificationLevel {
        self == .involvingMe && !knowingWhoYouAre ? .everything : self
    }
}

/// What a group's new activity should turn into on a lock screen, and what still has to be
/// looked up before that can be decided.
///
/// Pure, and deliberately apart from the fetching: this is the half with the rules in it, and
/// the half a suite can exercise in milliseconds without a server, a simulator or a clock.
public enum ActivityNotificationPlanner {

    public struct Plan: Sendable, Equatable {
        /// Worth telling someone about, oldest first — so that the newest is posted last and
        /// lands on top of the stack.
        public let certain: [Activity]

        /// New, and about an expense that still exists, so whether it involves this person is a
        /// question only that expense can answer. Oldest first, like `certain`.
        public let needsExpenseLookup: [Activity]

        /// What to remember once these have been dealt with.
        ///
        /// Taken from the activities themselves wherever there are any, rather than from the
        /// phone's clock: the times being compared are the server's, and an instance whose clock
        /// runs a minute ahead of the phone's would otherwise leave a window nothing is ever
        /// notified about.
        public let watermark: Date

        public init(certain: [Activity], needsExpenseLookup: [Activity], watermark: Date) {
            self.certain = certain
            self.needsExpenseLookup = needsExpenseLookup
            self.watermark = watermark
        }
    }

    /// Sorts a group's log into what to say, what to look up first, and where to resume.
    ///
    /// - Parameters:
    ///   - activities: what `groups.activities.list` returned, in any order.
    ///   - watermark: the newest activity this group has already dealt with. **Nil means this
    ///     group has never been looked at**, and nothing is notified — turning notifications on
    ///     must not announce a year of history. The watermark comes back set, so the next run
    ///     has a place to start from.
    ///   - level: the group's level, already resolved against `knowingWhoYouAre`.
    ///   - me: which participant the phone's owner is here, or nil if they have not said.
    public static func plan(
        activities: [Activity],
        since watermark: Date?,
        level: NotificationLevel,
        me: String?,
        now: Date = .now
    ) -> Plan {
        let resume = self.watermark(after: activities, since: watermark, now: now)

        guard let watermark, level != .nothing else {
            return Plan(certain: [], needsExpenseLookup: [], watermark: resume)
        }

        var certain: [Activity] = []
        var needsExpenseLookup: [Activity] = []

        for activity in activities.filter({ $0.time > watermark }).sorted(by: { $0.time < $1.time }) {
            switch verdict(on: activity, level: level, me: me) {
            case .tell: certain.append(activity)
            case .lookUpTheExpense: needsExpenseLookup.append(activity)
            case .sayNothing: break
            }
        }

        return Plan(certain: certain, needsExpenseLookup: needsExpenseLookup, watermark: resume)
    }

    /// Where to resume from, given what a run saw.
    ///
    /// Its own function because a group with nothing new — nearly every group on nearly every
    /// refresh — stops before it has fetched anything else, and still has to record that it
    /// looked. Two places computing "how far have I read" separately is how they come to
    /// disagree.
    public static func watermark(
        after activities: [Activity],
        since watermark: Date?,
        now: Date = .now
    ) -> Date {
        max(activities.map(\.time).max() ?? watermark ?? now, watermark ?? .distantPast)
    }

    private enum Verdict {
        case tell
        case sayNothing
        case lookUpTheExpense
    }

    private static func verdict(
        on activity: Activity,
        level: NotificationLevel,
        me: String?
    ) -> Verdict {
        // A kind this version has no sentence for. The log leaves those rows out rather than
        // inventing prose for them, and a notification with nothing to say would be worse than
        // a missing row — it interrupts.
        guard activity.activityType.isRecognised else { return .sayNothing }

        // Your own doing, at every level. The activity log names you on these lines because you
        // are who did them; being told about them is being told what you already know. This is
        // also what keeps a phone from notifying itself the moment it adds an expense.
        if let me, activity.participantId == me { return .sayNothing }

        switch level {
        case .nothing:
            return .sayNothing

        case .everything:
            return .tell

        case .involvingMe:
            switch activity.activityType {
            // A rename, a new participant, a change of currency: it lands on everybody in the
            // group equally, which is exactly what this level is not about. The line is that
            // "involves me" means an expense with me on it.
            case .updateGroup:
                return .sayNothing

            case .createExpense, .updateExpense, .deleteExpense:
                // `paidFor` is the answer, and the log does not carry it — the `expense` sent
                // beside each activity is the row itself, with no participants joined on. So the
                // expense has to be fetched, and for a deleted one it cannot be: that is the
                // `.tell` below. Being told about the deletion of an expense that turns out not
                // to have been yours is a smaller harm than never hearing that one that was has
                // gone, and deletions are rare enough for the trade to stay cheap.
                guard activity.expenseStillExists, activity.expenseId != nil else { return .tell }
                return .lookUpTheExpense

            case .unknown:
                return .sayNothing
            }
        }
    }
}
