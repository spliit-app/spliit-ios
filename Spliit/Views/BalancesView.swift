import SpliitAPI
import SpliitCore
import SwiftUI

/// Who is up and who is down, and the shortest set of payments that settles it.
struct BalancesView: View {

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: GroupDetailModel
    let onSettle: (Reimbursement) -> Void
    /// Opens the "who are you?" picker, which this screen shares with the information tab.
    let onIdentify: () -> Void

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        // Balances arrive separately from the group, and a participant list drawn before them
        // is a row of zeroes that reads as "everyone is settled up".
        if model.isLoadingGroup || model.isLoadingBalances {
            ProgressView().controlSize(.large)
        } else if model.didFailToLoad || model.didFailToLoadBalances {
            EmptyState(
                art: .icon("wifi.exclamationmark"),
                title: Text(errorTitle),
                description: Text(model.loadFailure ?? String(localized: "The server didn’t respond."))
            ) {
                Button("Try again") {
                    Task { await model.retry(using: app.client) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.ExpenseList.retryButton)
            }
        } else if let group = model.group {
            List {
                youSection(for: group)

                Section {
                    ForEach(Array(group.participants.enumerated()), id: \.element.id) { position, participant in
                        BalanceRow(
                            participant: participant,
                            position: position,
                            balance: model.balances[participant.id]
                                ?? Balance(paid: 0, paidFor: 0, total: 0),
                            largest: largestBalance,
                            formatter: model.moneyFormatter,
                            isYou: activeParticipant(in: group)?.id == participant.id
                        )
                    }
                } header: {
                    Text("Balances")
                } footer: {
                    // Not "what each participant paid, against what was spent on them", which
                    // is what this said and what the numbers are not. `groups.balances.list`
                    // returns the web app's *public* balances: figures derived from the
                    // suggested payments, where `paid` is what a participant will be handed and
                    // `paidFor` what they will hand over — so one of the two is always zero.
                    // The total is a settlement position, and only the total is real.
                    Text("Who is up and who is down, once every expense has been counted.")
                }

                Section {
                    if model.reimbursements.isEmpty {
                        Text("Everyone is settled up.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(AccessibilityID.Balances.settled)
                    } else {
                        ForEach(Array(model.reimbursements.enumerated()), id: \.offset) { index, reimbursement in
                            ReimbursementRow(
                                index: index,
                                reimbursement: reimbursement,
                                from: model.participant(reimbursement.from),
                                fromPosition: model.participantPosition(reimbursement.from),
                                to: model.participant(reimbursement.to),
                                toPosition: model.participantPosition(reimbursement.to),
                                formatter: model.moneyFormatter,
                                onSettle: { onSettle(reimbursement) }
                            )
                        }
                    }
                } header: {
                    Text("Suggested payments")
                } footer: {
                    if !model.reimbursements.isEmpty {
                        Text("The fewest payments that settle the group.")
                    }
                }
            }
            .refreshable { await model.reloadAfterExpenseChange(using: app.client) }
            // Settling a payment moves every balance at once. This is what lets the amounts roll
            // to their new values and the bars slide, rather than the screen simply being
            // different the next time you look at it.
            .animation(Motion.base, value: model.balances)
        }
    }

    // MARK: - You

    /// The group's balances, read from where the user stands in it.
    ///
    /// This sits above the list rather than inside it because it answers a different question.
    /// The list below says how the group is doing; this says how *you* are doing, which is the
    /// only line most people open the tab for — and until somebody says who they are, it is the
    /// invitation to.
    private func youSection(for group: SpliitAPI.Group) -> some View {
        Section {
            if let you = activeParticipant(in: group) {
                summary(for: model.balances[you.id] ?? Balance(paid: 0, paidFor: 0, total: 0))
            }

            Button(action: onIdentify) { identityLabel(for: group) }
                .accessibilityIdentifier(AccessibilityID.ActiveUser.balancesButton)
        } header: {
            Text("You")
        } footer: {
            // Dropped at the accessibility sizes, where this paragraph is a screenful on its
            // own — and what it would push off the bottom is the balances. It explains a button
            // whose label already says what it does, which makes it the part that can go.
            if activeParticipant(in: group) == nil, !dynamicTypeSize.isAccessibilitySize {
                Text("Pick yourself once and this group is read from where you stand: your own balance first, and your name already filled in on a new expense.")
            }
        }
    }

    /// The row that opens the picker, saying what it would be changing.
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

    /// The headline: which way the money goes, and how much of it. The amount is shown unsigned
    /// — the sentence above it is what carries the direction, and "You owe −$50.00" says it
    /// twice and contradicts itself doing so.
    ///
    /// It is one number and stays one number. "You paid X, and Y was spent on you" was written
    /// here first and was false: the `paid` and `paidFor` this endpoint returns are the
    /// settlement's, not the group's — see the footer below. The real pair lives on the totals
    /// tab, which asks `groups.stats.get` for it.
    private func summary(for balance: Balance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(direction(of: balance))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.ActiveUser.direction)

            Money(
                value: model.moneyFormatter.string(minorUnits: abs(balance.total)),
                size: .hero,
                sign: Money.Sign(balance: balance.total)
            )
            .accessibilityIdentifier(AccessibilityID.ActiveUser.total)
        }
        .padding(.vertical, 4)
    }

    private func direction(of balance: Balance) -> LocalizedStringKey {
        if balance.total > 0 { "You are owed" }
        else if balance.total < 0 { "You owe" }
        else { "You’re settled up" }
    }

    /// Who the user says they are here, when the group still has them.
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

    /// The group can arrive and its balances still fail, so name whichever one is missing.
    private var errorTitle: LocalizedStringKey {
        model.didFailToLoad ? "Couldn’t load this group" : "Couldn’t load the balances"
    }

    /// The scale for the bars: the biggest absolute balance in the group.
    private var largestBalance: Int {
        max(model.balances.values.map { abs($0.total) }.max() ?? 0, 1)
    }
}

/// A diverging bar: owed to the right of centre, owing to the left.
private struct BalanceRow: View {
    let participant: Participant
    let position: Int
    let balance: Balance
    let largest: Int
    let formatter: MoneyFormatter
    let isYou: Bool

    @ScaledMetric private var barHeight: CGFloat = 8

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Monogram(name: participant.name, position: position, size: 26)

            VStack(alignment: .leading, spacing: 6) {
                AdaptiveHStack {
                    HStack(spacing: 6) {
                        Text(participant.name)
                            .accessibilityIdentifier(
                                AccessibilityID.Balances.participantName(participant.id)
                            )
                            .accessibilityValue(direction)

                        // Left visible to VoiceOver: which row is yours is exactly the kind of
                        // thing a glance gets for free and a screen reader gets not at all.
                        if isYou {
                            Text("You")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: .capsule)
                                .accessibilityIdentifier(
                                    AccessibilityID.ActiveUser.badge(participant.id)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Money(
                        value: formatter.string(minorUnits: balance.total),
                        sign: Money.Sign(balance: balance.total)
                    )
                    .accessibilityIdentifier(
                        AccessibilityID.Balances.participantAmount(participant.id)
                    )
                }

                bar
            }
        }
        .padding(.vertical, 2)
    }

    private var bar: some View {
        GeometryReader { geometry in
            let half = geometry.size.width / 2
            let fraction = Double(abs(balance.total)) / Double(largest)
            let width = max(half * fraction, balance.total == 0 ? 0 : 2)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1)
                    .offset(x: half)

                Capsule()
                    .fill(tint)
                    .frame(width: width)
                    .offset(x: balance.total < 0 ? half - width : half)
            }
        }
        .frame(height: barHeight)
        .accessibilityHidden(true)
    }

    /// Which side of zero this is. On screen the tint and the minus sign carry it, and the bar
    /// says it a third time — but the bar is decorative to VoiceOver and a colour cannot be
    /// read aloud, which leaves a lone minus sign doing all the work.
    ///
    /// This is the amount's meaning, so it belongs on the amount — except that the UI tests
    /// assert the amount's label is exactly the formatted money. Hanging it on the name as a
    /// value keeps both: "Ana, is owed" then "$20.00".
    private var direction: Text {
        if balance.total > 0 { Text("is owed") }
        else if balance.total < 0 { Text("owes") }
        else { Text("settled up") }
    }

    /// The same tint the amount above it uses, so the bar and the number are obviously one
    /// statement rather than two coincidentally coloured things.
    private var tint: Color {
        Money.Sign(balance: balance.total).tint
    }
}

private struct ReimbursementRow: View {
    let index: Int
    let reimbursement: Reimbursement
    let from: Participant?
    let fromPosition: Int
    let to: Participant?
    let toPosition: Int
    let formatter: MoneyFormatter
    let onSettle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveHStack(spacing: 12) {
                // Who pays whom, as a picture. The sentence beside it says the same thing, which
                // is why this pair is invisible to VoiceOver rather than read out twice.
                HStack(spacing: 6) {
                    Monogram(name: from?.name ?? "", position: fromPosition, size: 24)
                    Image(systemName: "arrow.forward")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Monogram(name: to?.name ?? "", position: toPosition, size: 24)
                }
                .accessibilityHidden(true)

                Text("\(from?.name ?? "—") owes \(to?.name ?? "—")")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.Balances.reimbursement(index))

                Money(
                    value: formatter.string(minorUnits: reimbursement.amount),
                    size: .lead
                )
            }

            Button("Mark as paid", action: onSettle)
                .font(.subheadline)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityID.Balances.markAsPaid(index))
                .accessibilityLabel(settleLabel)
        }
        .padding(.vertical, 2)
    }

    /// Every suggested payment carries a button reading "Mark as paid". Read out of the visual
    /// context of its row they are indistinguishable, so each one names the payment it settles.
    private var settleLabel: Text {
        Text(
            "Mark \(from?.name ?? "—")’s payment of \(formatter.string(minorUnits: reimbursement.amount)) to \(to?.name ?? "—") as paid"
        )
    }
}
