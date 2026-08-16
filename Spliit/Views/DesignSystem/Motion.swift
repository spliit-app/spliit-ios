import SwiftUI

/// The speed at which content changes in place.
///
/// The design system names three durations — 120ms for a press, 220ms for a fade, 350ms for a
/// push. Two of them are already the platform's: a button's press highlight and a navigation push
/// are animated by iOS before anyone writes a line, and restating their timings here would only
/// invite someone to override them. What is left is the case iOS has no opinion about, because it
/// belongs to the app rather than the navigation: a row leaving a list, a balance moving.
///
/// Nothing bounces. A spring on a row that is disappearing reads as a toy, and this is an app
/// people open at a restaurant table.
enum Motion {

    /// Content arriving, leaving, or changing value in place.
    static let base = Animation.easeInOut(duration: 0.22)
}
