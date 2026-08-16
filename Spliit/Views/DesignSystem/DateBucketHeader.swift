import SwiftUI

/// The heading above a run of expenses — "This week", "Last month", "Older".
///
/// A grouped `List` gives these headings for free and draws them the same way every app does.
/// Small caps and wide tracking make them read as rules between the expenses rather than as
/// entries among them, which is the job a date bucket is doing.
struct DateBucketHeader: View {

    /// Already localised, in its natural case.
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            // 0.06em at caption's 12pt. Tracking does not scale with Dynamic Type, and at these
            // sizes it does not need to — the letters move apart, the gap between them does not.
            .tracking(0.72)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            // Capitals are a typographic treatment, not a change to the words: VoiceOver should
            // still hear "This week". This has to be the string overload — `textCase` is an
            // environment value, so a `Text` passed here comes back uppercased along with the
            // one on screen, which is exactly the trap this comment exists to describe.
            .accessibilityLabel(title)
    }
}
