import SwiftUI

/// The four things the app is allowed to say through the Taptic Engine.
///
/// Haptics are cheap to add and expensive to live with: a phone that buzzes at every tap teaches
/// people to ignore it, and the one buzz that mattered goes with it. So these are attached to
/// *outcomes* rather than to gestures — the moments where something was committed, undone, or
/// refused, and where the screen alone may not have said so yet.
///
/// Deliberately absent: tapping a row, switching tabs, opening a sheet, typing in the search
/// field. iOS already gives a button its press feedback, and the rest is confirmation of things
/// nobody was in doubt about.
enum Haptics {

    /// An expense reached the server — created, edited, or a reimbursement marked as paid. The
    /// sheet closes on the same beat, so this is the only confirmation of the round trip.
    static let saved = SensoryFeedback.success

    /// A save was refused before it was sent, because the form does not add up. The reason is on
    /// screen; this is what says to go and look.
    static let refused = SensoryFeedback.error

    /// A row was swiped away. Soft rather than a notification: it reports a thing moved, not a
    /// thing decided — and for five seconds it is not decided.
    static let deleted = SensoryFeedback.impact(flexibility: .soft)

    /// The delete was taken back.
    static let undone = SensoryFeedback.success
}
