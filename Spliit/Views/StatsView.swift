import SpliitAPI
import SpliitCore
import SwiftUI

/// What the group has spent, and how much of it is yours.
///
/// Three numbers, and they are the only three the API can answer: `groups.stats.get` sums the
/// expenses themselves, which is what makes it the one endpoint that knows what anybody actually
/// paid. The balances tab next door looks like it knows and does not — its `paid` and `paidFor`
/// come from the suggested payments, so one of the pair is always zero.
///
/// Two of the three are a participant's, so the tab is worth one number until somebody says who
/// they are — which is why the invitation to answer is on this screen too, below the total it
/// unlocks rather than in front of it.
///
/// The web app calls this tab *Stats* and the card inside it *Totals*. On a phone the second
/// word is the one that fits: "Statistiques" beside "Informations" leaves a French tab bar with
/// two truncated labels, and totals is what the screen actually holds. The analytics screen name
/// stays the web's route, `group-stats`, so the two Plausible sites still read side by side.
struct StatsView: View {

    @Environment(AppModel.self) private var app
    let model: GroupDetailModel
    /// Opens the "who are you?" picker, which this screen shares with the balances and
    /// information tabs.
    let onIdentify: () -> Void

    var body: some View {
        content
            // `.task(id:)` is what makes the request lazy — it is a fourth call on a screen that
            // already makes three, and the other tabs never need it — and what asks again when
            // the answer to "who are you?" changes, since two of the three numbers are theirs.
            .task(id: statsKey) {
                guard statsKey != nil else { return }
                await model.loadStats(for: activeParticipantID, using: app.client)
            }
            // Its own task, keyed on the group alone: what the group spent on food does not
            // change with who is asking, so this must not be re-swept every time somebody
            // answers the picker.
            .task(id: model.group?.id) {
                guard model.group != nil else { return }
                await model.loadCategorySpending(using: app.client)
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.statsUnavailable {
            // Not a failure, so not a retry: an instance that has never heard of the procedure
            // will not have heard of it a second time either. No identifier, because there is no
            // leaf to hang one on — an `EmptyState` with no action is a title and a paragraph,
            // and an identifier on the state itself would be stamped over both.
            EmptyState(
                art: .icon("chart.bar.xaxis"),
                title: Text("No totals on this server"),
                description: Text(
                    "This Spliit instance doesn’t offer them. Everything else in the group works as usual."
                )
            ) {}
        } else if model.isLoadingGroup || model.isLoadingStats {
            ProgressView().controlSize(.large)
        } else if model.didFailToLoad || model.didFailToLoadStats {
            EmptyState(
                art: .icon("wifi.exclamationmark"),
                title: Text(errorTitle),
                description: Text(
                    model.loadFailure ?? String(localized: "The server didn’t respond.")
                )
            ) {
                // Whichever one failed is the one to try again. Reloading the group also brings
                // the totals back on its own: `statsKey` goes from nil to an answer, which is
                // what the task above is waiting for.
                Button("Try again") {
                    Task {
                        if model.didFailToLoad {
                            await model.retry(using: app.client)
                        } else {
                            await model.refreshStats(
                                for: activeParticipantID, using: app.client
                            )
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.Stats.retryButton)
            }
        } else if let group = model.group, let stats = model.stats {
            List {
                groupSection(stats)
                youSection(stats, in: group)
                categorySection(stats)
            }
            .refreshable {
                async let totals: Void = model.refreshStats(
                    for: activeParticipantID, using: app.client
                )
                async let categories: Void = model.refreshCategorySpending(using: app.client)
                _ = await (totals, categories)
            }
            // The totals move together when an expense is added from another tab, so let them
            // roll rather than simply be different the next time you look.
            .animation(Motion.base, value: stats)
        }
    }

    // MARK: - The group

    private func groupSection(_ stats: Spliit.GroupStatsResponse) -> some View {
        Section {
            total(
                label: stats.totalGroupSpendings < 0
                    ? "Total group earnings" : "Total group spending",
                labelIdentifier: AccessibilityID.Stats.groupTotalLabel,
                minorUnits: stats.totalGroupSpendings,
                identifier: AccessibilityID.Stats.groupTotal,
                size: .hero
            )
        } header: {
            Text("The group")
        } footer: {
            Text("Settling up is not spending, so reimbursements are left out of every figure here.")
        }
    }

    // MARK: - You

    /// Your two numbers, or the question that answers them.
    ///
    /// Below the group's total rather than above it, unlike the balances tab: there the personal
    /// line is the whole reason to open the screen, here it is the second half of one the group
    /// already answered.
    @ViewBuilder
    private func youSection(
        _ stats: Spliit.GroupStatsResponse,
        in group: SpliitAPI.Group
    ) -> some View {
        // Both halves have to agree before a personal figure is drawn. Changing the answer moves
        // the identity at once and the totals a request later, so for that moment the two
        // disagree — and each direction of the disagreement is a way to be wrong. Ana's numbers
        // must not sit under "Nobody" on the way out, and the row must not be blank under "Ana"
        // on the way back in.
        let you = activeParticipant(in: group)

        Section {
            if you != nil, let spendings = stats.totalParticipantSpendings {
                total(
                    label: spendings < 0 ? "Your earnings" : "Your spending",
                    labelIdentifier: AccessibilityID.Stats.yourSpendingLabel,
                    minorUnits: spendings,
                    identifier: AccessibilityID.Stats.yourSpending,
                    size: .lead,
                    fraction: (
                        of: stats.totalGroupSpendings,
                        identifier: AccessibilityID.Stats.yourSpendingFraction
                    )
                )
            }

            if you != nil, let share = shareInMinorUnits(of: stats) {
                total(
                    label: "Your share",
                    labelIdentifier: AccessibilityID.Stats.yourShareLabel,
                    minorUnits: share,
                    identifier: AccessibilityID.Stats.yourShare,
                    size: .lead,
                    fraction: (
                        of: stats.totalGroupSpendings,
                        identifier: AccessibilityID.Stats.yourShareFraction
                    )
                )
            }

            Button(action: onIdentify) { identityLabel(for: group) }
                .accessibilityIdentifier(AccessibilityID.ActiveUser.statsButton)
        } header: {
            Text("You")
        } footer: {
            if you == nil {
                Text("Pick yourself and this tab also says what you have paid, and what your share of the group came to.")
            } else {
                Text("What you paid, against what was spent on you. The difference is your balance.")
            }
        }
    }

    // MARK: - By category

    /// Where the money went, folded on the client from the expenses themselves.
    ///
    /// Only drawn once it reconciles with the group's own total — see
    /// `categorySpendingReconciles`. A breakdown printed under a total it does not add up to
    /// invites exactly one question, and "because the sweep stopped early" is not an answer
    /// worth putting on a phone.
    @ViewBuilder
    private func categorySection(_ stats: Spliit.GroupStatsResponse) -> some View {
        if model.categorySpendingReconciles {
            Section {
                ForEach(model.categorySpending) { spending in
                    CategoryRow(
                        spending: spending,
                        groupTotal: stats.totalGroupSpendings,
                        formatter: model.moneyFormatter
                    )
                }
            } header: {
                Text("By category")
            } footer: {
                Text("Every bar on this screen is a slice of the same total, so the lengths compare straight down the page.")
            }
        } else if model.categoryLoad.isLoading {
            // A placeholder rather than nothing: this sweep reads every expense in the group, so
            // it can land after the three figures above and a section appearing unannounced
            // moves the page under a thumb already on it.
            Section {
                ProgressView()
            } header: {
                Text("By category")
            }
        } else if model.categoryLoad.didFail {
            Section {
                Label(
                    model.categoryLoad.failure
                        ?? String(localized: "The server didn’t respond."),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.Stats.categoryFailed)
            } header: {
                Text("By category")
            }
        }
        // Otherwise nothing at all — a group with no expenses has no breakdown to draw.
    }

    /// The row that opens the picker, saying what it would be changing. The same three states as
    /// on the balances tab, worded the same way.
    @ViewBuilder
    private func identityLabel(for group: SpliitAPI.Group) -> some View {
        if let you = activeParticipant(in: group) {
            LabeledContent("You", value: you.name)
        } else if storedIdentity(in: group) == .nobody {
            LabeledContent("You", value: String(localized: "Nobody"))
        } else {
            Label("Say who you are", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    // MARK: - One figure

    /// A caption, the amount under it, and — for the two that are a slice of the group's — how
    /// big a slice.
    ///
    /// Unsigned, like the balance headline next door and for the same reason: the caption above
    /// already says which way it goes, and "Total group earnings −$40.00" says it twice while
    /// contradicting itself. A total has no direction to tint either, so these carry no colour.
    private func total(
        label: LocalizedStringKey,
        labelIdentifier: String,
        minorUnits: Int,
        identifier: String,
        size: Money.Size,
        fraction: (of: Int, identifier: String)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(labelIdentifier)

            Money(
                value: model.moneyFormatter.string(minorUnits: abs(minorUnits)),
                size: size
            )
            .accessibilityIdentifier(identifier)

            if let fraction, let slice = groupSlice(of: minorUnits, in: fraction.of) {
                ShareOfGroup(fraction: slice, identifier: fraction.identifier)
            }
        }
        .padding(.vertical, 4)
    }

    /// The share as whole minor units, which is what the formatter takes.
    ///
    /// Today's server already sends a whole number. One older than the web app's *Shares* change
    /// sends thirds of a cent, and a third of a cent is not a thing to draw — the web app rounds
    /// the same value for the same reason.
    private func shareInMinorUnits(of stats: Spliit.GroupStatsResponse) -> Int? {
        guard let share = stats.totalParticipantShare, share.isFinite else { return nil }
        return Int(exactly: share.rounded())
    }

    // MARK: - Who you are

    /// What the totals are an answer to, or nil while there is no question to ask yet.
    ///
    /// The group has to be in here as well as the participant, because who you are cannot be
    /// resolved until its participant list has arrived. Keyed on the participant alone, a tab
    /// opened while the group was still loading would ask for the group's total with nobody's
    /// share beside it — and, the key never having moved, never ask again.
    private var statsKey: String? {
        guard model.group != nil else { return nil }
        return activeParticipantID ?? ""
    }

    private var activeParticipantID: String? {
        guard let group = model.group else { return nil }
        return activeParticipant(in: group)?.id
    }

    private func activeParticipant(in group: SpliitAPI.Group) -> Participant? {
        guard case .participant(let id)? = storedIdentity(in: group) else { return nil }
        return model.participant(id)
    }

    /// The stored answer, read against the group — which is what turns a participant who has
    /// since been removed back into an unanswered question.
    private func storedIdentity(in group: SpliitAPI.Group) -> ActiveParticipant? {
        ActiveParticipant.resolve(
            app.recentGroups.activeParticipant(inGroup: model.groupID),
            in: group.participants
        )
    }

    /// The group can arrive and its totals still fail, so name whichever one is missing.
    private var errorTitle: LocalizedStringKey {
        model.didFailToLoad ? "Couldn’t load this group" : "Couldn’t load the totals"
    }
}

/// How much of the group's spending a figure is, or nothing when the question has no answer: a
/// group that has spent nothing has no slices, and one that has taken in more than it spent has
/// no scale to measure against.
///
/// One function, because there is one denominator on this screen. The two personal figures and
/// every category bar are all a slice of the group's total, which is what lets their lengths be
/// compared straight down the page — two bars sharing a screen and not a scale is a way to
/// mislead with no marking on it.
///
/// Clamped, because neither end is impossible. A group whose expenses net out below what one
/// person paid would put a bar past its own track, and a category that came to a refund would
/// put one behind the start of it.
private func groupSlice(of value: Int, in groupTotal: Int) -> Double? {
    guard groupTotal > 0 else { return nil }
    return min(max(Double(value) / Double(groupTotal), 0), 1)
}

/// One category, its spend, and how much of the group that is.
///
/// Laid out like a balance row — glyph, name, amount, bar — because it is the same shape of
/// statement and the two tabs sit next to each other. The percentage is not written out here the
/// way it is under the two figures above: those are one number each and the caption earns its
/// place; a dozen of them down a list is noise, and the bar is what the eye is comparing anyway.
/// VoiceOver still gets it, as a value on the name.
private struct CategoryRow: View {

    let spending: CategorySpending
    let groupTotal: Int
    let formatter: MoneyFormatter

    @ScaledMetric private var barHeight: CGFloat = 6

    private var category: ExpenseCategory {
        ExpenseCategory(id: spending.categoryID, grouping: spending.grouping, name: spending.name)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CategoryIcon(category: category, size: 26)

            VStack(alignment: .leading, spacing: 6) {
                AdaptiveHStack {
                    Text(category.displayName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(
                            AccessibilityID.Stats.categoryName(spending.categoryID)
                        )
                        .accessibilityValue(shareDescription)

                    // Signed, unlike the three figures above: nothing here says which way a
                    // category went, so the minus has to. A total is not a direction, so it
                    // takes no colour either.
                    Money(value: formatter.string(minorUnits: spending.total))
                        .accessibilityIdentifier(
                            AccessibilityID.Stats.categoryAmount(spending.categoryID)
                        )
                }

                if let slice = groupSlice(of: spending.total, in: groupTotal) {
                    bar(slice)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func bar(_ slice: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(geometry.size.width * slice, slice > 0 ? 2 : 0))
            }
        }
        .frame(height: barHeight)
        .accessibilityHidden(true)
    }

    /// What the bar says, for the reader who cannot see a length.
    private var shareDescription: Text {
        guard let slice = groupSlice(of: spending.total, in: groupTotal) else { return Text("") }
        return Text("\(slice.formatted(.percent.precision(.fractionLength(0)))) of the group")
    }
}

/// A slice of the group's spending, as a bar and as a sentence.
///
/// The bar alone would be decorative — a length with nothing to measure it against — so the
/// percentage is written out beside it, and the bar is what VoiceOver skips.
private struct ShareOfGroup: View {

    let fraction: Double
    /// Carried down to the caption rather than set on this view: an identifier on the stack
    /// would be stamped onto the bar as well, and the bar is the half that is meant to be
    /// invisible.
    let identifier: String

    @ScaledMetric private var barHeight: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(geometry.size.width * fraction, fraction > 0 ? 2 : 0))
                }
            }
            .frame(height: barHeight)
            .accessibilityHidden(true)

            Text("\(fraction.formatted(.percent.precision(.fractionLength(0)))) of the group")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(identifier)
        }
        .padding(.top, 2)
    }
}
