import SwiftUI

/// What a delete leaves behind for a few seconds.
///
/// A confirmation dialog asks a question the answer to which is almost always yes; this asks
/// nothing, and is there for the times the answer was no. It sits above the tab bar so it reads
/// as belonging to the screen rather than to the row that has gone.
struct UndoBar: View {

    let message: Text
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            message
                .font(.subheadline)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button("Undo", action: action)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier(AccessibilityID.ExpenseList.undoButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
    }
}

extension View {
    /// Hangs the undo bar under a screen that can delete an expense.
    ///
    /// Applied to a tab's content rather than to the `TabView`: on the `TabView` it lands in the
    /// tab bar's own strip and the two draw on top of each other. Inside a tab it stacks above
    /// whatever bar that tab already has — the tab bar here, the search field in the search tab.
    func expenseUndoBar(_ model: GroupDetailModel) -> some View {
        modifier(ExpenseUndoBar(model: model))
    }
}

private struct ExpenseUndoBar: ViewModifier {

    let model: GroupDetailModel

    /// Undo and the window closing both end with nothing pending, so the pending value alone
    /// cannot tell them apart. Counting the undos does.
    @State private var undoCount = 0

    func body(content: Content) -> some View {
        content
            .safeAreaBar(edge: .bottom) {
                if let pending = model.pendingDeletion {
                    UndoBar(message: Text("Deleted “\(pending.expense.title)”")) {
                        undoCount += 1
                        model.undoDelete()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.base, value: model.pendingDeletion)
            // Only on the way in. Going quiet again is the window closing, which is not an event
            // anyone did — and a buzz five seconds after a swipe belongs to nothing on screen.
            .sensoryFeedback(trigger: model.pendingDeletion) { previous, current in
                previous == nil && current != nil ? Haptics.deleted : nil
            }
            .sensoryFeedback(Haptics.undone, trigger: undoCount)
    }
}

#Preview {
    Color(.systemGroupedBackground)
        .safeAreaBar(edge: .bottom) {
            UndoBar(message: Text("Deleted “Pizza night”")) {}
        }
}
