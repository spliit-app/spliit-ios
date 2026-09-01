import SpliitAPI
import SpliitCore
import SwiftUI

/// What the search tab shows: the field, and whatever the server matched.
///
/// The results are their own list rather than a filtered view of the expenses tab. Both tabs
/// exist at once, and narrowing the shared array would empty the list sitting behind the search
/// field.
///
/// **Why the field is built here rather than with `.searchable`.** The system modifier puts its
/// field in a navigation bar, and hosts the iOS 26 bottom-docked version only when the `TabView`
/// owning the search tab is the root of the scene. This one is not: the group screen is *pushed*
/// onto the groups list, and the roadmap's zoom transition depends on that push. Applied to the
/// `TabView`, to the tab's content, or to a `NavigationStack` nested inside the tab, `.searchable`
/// produced no field at all here — and the nested stack popped the whole screen, which is the
/// trap CLAUDE.md documents. So the field is ours: a glass capsule in a bottom safe-area inset,
/// which keyboard avoidance lifts above the keyboard for free.
struct ExpenseSearchView: View {

    @Environment(AppModel.self) private var app

    /// The instance this group is on. Every request from this screen goes through it: a group ID
    /// only means anything to the server that issued it.
    private var client: TRPCClient { app.client(forGroup: model.groupID) }
    let model: GroupDetailModel
    @Binding var query: String
    /// Whether the search tab is the one on screen. A `TabView` keeps every tab's content alive,
    /// so this view has to be told when it is being looked at — hiding the tab bar unconditionally
    /// hides it for the other tabs too, and leaves no way back.
    let isActive: Bool
    let onEdit: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        // The `ZStack` is load-bearing. `content` switches between the prompt, the results and
        // the empty state as the search runs, and hanging the bar off a view whose shape changes
        // takes the field's identity with it: the first results arriving rebuilt the field,
        // which dropped keyboard focus and the keyboard with it, one character in. The stack
        // gives the modifiers below something whose identity never changes.
        ZStack {
            // The same ground the lists stand on. A `List` brings the grouped background with
            // it; the prompt, the spinner and the empty states bring nothing, so the screen went
            // white between searches and grey once results arrived — one flicker per keystroke.
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            content
        }
        // Inside the search field's bar, so a deleted result's way back sits above the field
        // rather than under it.
        .expenseUndoBar(model)
        // `safeAreaBar`, not `safeAreaInset`: the iOS 26 bar variant is the one that stays
        // interactive. Under `safeAreaInset` the field and both buttons render correctly,
        // report themselves hittable, and silently swallow every tap — by element and by
        // coordinate alike. It is the inset that eats them, not the glass.
        .safeAreaBar(edge: .bottom) { searchBar }
        // The tab bar and the field both want the bottom of the screen. Standing down while
        // searching is what the system's own search tab does when it morphs the bar into a
        // field; the cancel button beside the field is the way back to the tabs.
        .toolbar(isActive ? .hidden : .automatic, for: .tabBar)
        // Opening search should put the caret in the field, and every re-entry counts as an
        // opening — the content is never torn down, so `onAppear` would only ever fire once.
        //
        // The screen view is reported from here for the same reason, rather than with
        // `trackScreen`: a tab's content can be built before anyone has looked at it, and a
        // search screen counted on every group opened would be a search nobody ran.
        .task(id: isActive) {
            isFieldFocused = isActive
            if isActive {
                Analytics.shared.screen(.groupSearch)
            }
        }
    }

    /// Driven by what is in the field, not by what the model has searched for.
    ///
    /// The two disagree for the length of the debounce, and deciding on the model alone put the
    /// "Search this group" prompt back on screen between characters — the field said one thing
    /// and the screen behind it said another.
    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            EmptyState(
                art: .icon("magnifyingglass"),
                title: Text("Search this group"),
                description: Text("Find an expense by its title.")
            )
        } else if model.didFailToSearch {
            EmptyState(
                art: .icon("wifi.exclamationmark"),
                title: Text("Couldn’t search"),
                description: Text(
                    model.searchLoad.failure ?? String(localized: "The server didn’t respond.")
                )
            )
        } else if model.hasNoMatches {
            EmptyState(
                art: .icon("magnifyingglass"),
                title: Text("No matching expenses"),
                // Titles, specifically: the server matches `title` and nothing else, so
                // promising a search of "expenses" would promise more than it does.
                description: Text("No expense here has “\(model.filter ?? "")” in its title.")
            )
        } else if model.searchResults.isEmpty {
            // Typed, but nothing has come back yet — the debounce is still running or the
            // request is in flight. Narrowing an existing search skips this: the previous
            // results stay up until the new ones replace them.
            ProgressView().controlSize(.large)
        } else {
            results
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchBar: some View {
        // Two glass surfaces a few points apart, which is the case the container exists for:
        // inside one they sample the same backdrop and bend towards each other as the gap
        // closes, instead of each refracting the screen on its own like two unrelated panes.
        GlassEffectContainer(spacing: 10) {
            searchBarContent
        }
        .padding(.horizontal, 16)
        // The keyboard arrives right under the bar, and without this the field and the top row
        // of keys share an edge — the glass capsule reads as part of the keyboard rather than
        // as the thing being typed into. Matches the gap between the field and its cancel
        // button, so the bar keeps one rhythm.
        .padding(.bottom, 10)
        .animation(Motion.base, value: query.isEmpty)
    }

    /// The height of the field, and so of the button beside it. The field is a line of body text
    /// (22pt at the default size) plus its padding; the button is given the same, rather than the
    /// larger size the glass style reaches on its own.
    private var barHeight: CGFloat { 22 + fieldPadding * 2 }
    private let fieldPadding: CGFloat = 11

    private var searchBarContent: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Search expenses", text: $query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFieldFocused)
                    .accessibilityIdentifier(AccessibilityID.ExpenseSearch.field)

                if !query.isEmpty {
                    Button {
                        query = ""
                        isFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear search"))
                    .accessibilityIdentifier(AccessibilityID.ExpenseSearch.clearButton)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, fieldPadding)
            .glassEffect(.regular, in: .capsule)

            // Sized to the field rather than left to its own devices. `.buttonStyle(.glass)` pads
            // generously around whatever it is given — a 44pt glyph frame came out 68×58 beside a
            // 44pt field, which made the way *out* of search the biggest thing in the bar.
            //
            // `.interactive()` is what the button style would have provided: the glass responds
            // to a press rather than sitting there.
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: barHeight, height: barHeight)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(Text("Cancel search"))
            .accessibilityIdentifier(AccessibilityID.ExpenseSearch.cancelButton)
        }
    }

    private var results: some View {
        List {
            ForEach(model.searchSections, id: \.group) { section in
                Section {
                    ForEach(section.expenses) { expense in
                        Button {
                            onEdit(expense.id)
                        } label: {
                            ExpenseRow(
                                expense: expense,
                                payerPosition: model.participantPosition(expense.paidBy.id),
                                formatter: model.moneyFormatter
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.requestDelete(expense, using: client) }
                            }
                        }
                    }
                } header: {
                    DateBucketHeader(title: section.group.title)
                }
            }

            if model.hasMoreSearchResults {
                HStack {
                    Spacer()
                    ProgressView()
                        .accessibilityLabel(Text("Loading more results"))
                    Spacer()
                }
                .task { await model.loadNextSearchPage(using: client) }
            }
        }
        // Typing changes the results under the thumb; letting them cut rather than animate keeps
        // a fast typist from watching rows slide in and out of a list they are still narrowing.
        .scrollDismissesKeyboard(.interactively)
    }
}
