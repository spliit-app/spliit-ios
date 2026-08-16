import SwiftUI

/// The three speeds the app moves at.
///
/// Most of the motion in an iOS app is the platform's: a push, a tab switch and a button's press
/// highlight are all animated before anyone writes a line. These are for the handful of places
/// where state changes on its own — a deleted row, a balance that has just moved — and they exist
/// so those places agree with each other and with the system rather than each inventing a speed.
///
/// Nothing here bounces. A spring on a row that is disappearing reads as a toy, and this is an app
/// people open at a restaurant table to find out who owes what.
enum Motion {

    /// Press and highlight.
    static let fast = Animation.easeOut(duration: 0.12)

    /// Fades, and content arriving or leaving a list.
    static let base = Animation.easeInOut(duration: 0.22)

    /// A push, or the zoom into a group.
    static let slow = Animation.easeInOut(duration: 0.35)
}
