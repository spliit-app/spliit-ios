import Foundation
import SpliitAPI

/// One line of a group's history, written out.
///
/// Two places say this now — the activity log and a notification — and they have to say it the
/// same way: a notification that reads differently from the row it will take you to is a
/// notification you have to read twice. So the sentences live here rather than in either screen.
///
/// Whole sentences, interpolated. Where a name sits in one, and whether the title comes before or
/// after it, is the translation's business and not the call site's.
enum ActivitySentence {

    /// - Parameter participantName: whoever did it, already resolved against the group. Nil when
    ///   the client that made the change did not say who it was — which is what "Someone" is for,
    ///   and is accurate rather than evasive: `participantId` is optional on all four mutating
    ///   procedures and the server keeps no other record.
    static func text(for activity: Activity, participantName: String?) -> String {
        let who = participantName ?? String(localized: "Someone")
        // The title as it was when this was recorded, which is the point — renaming an expense
        // leaves the old name on the line describing its creation.
        let what = activity.title ?? ""

        return switch activity.activityType {
        case .createExpense: String(localized: "\(who) added “\(what)”.")
        case .updateExpense: String(localized: "\(who) updated “\(what)”.")
        case .deleteExpense: String(localized: "\(who) deleted “\(what)”.")
        case .updateGroup: String(localized: "\(who) changed the group settings.")
        // Never drawn and never posted: both callers drop the kinds this version has no sentence
        // for, rather than inventing one for them here.
        case .unknown: ""
        }
    }
}
