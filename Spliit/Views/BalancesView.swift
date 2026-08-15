import Charts
import SpliitAPI
import SpliitCore
import SwiftUI

/// Who is up and who is down, and the shortest set of payments that settles it.
struct BalancesView: View {

    @Environment(AppModel.self) private var app
    let model: GroupDetailModel
    let onSettle: (Reimbursement) -> Void

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
            ContentUnavailableView {
                Label(errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(model.loadFailure ?? String(localized: "The server didn’t respond."))
            } actions: {
                Button("Try again") {
                    Task { await model.retry(using: app.client) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.ExpenseList.retryButton)
            }
        } else if let group = model.group {
            List {
                Section {
                    ForEach(group.participants) { participant in
                        BalanceRow(
                            participant: participant,
                            balance: model.balances[participant.id]
                                ?? Balance(paid: 0, paidFor: 0, total: 0),
                            largest: largestBalance,
                            formatter: model.moneyFormatter
                        )
                    }
                } header: {
                    Text("Balances")
                } footer: {
                    Text("What each participant paid, against what was spent on them.")
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
                                to: model.participant(reimbursement.to),
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
        }
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
    let balance: Balance
    let largest: Int
    let formatter: MoneyFormatter

    @ScaledMetric private var barHeight: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AdaptiveHStack {
                Text(participant.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(
                        AccessibilityID.Balances.participantName(participant.id)
                    )
                    .accessibilityValue(direction)

                Text(formatter.string(minorUnits: balance.total))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .accessibilityIdentifier(
                        AccessibilityID.Balances.participantAmount(participant.id)
                    )
            }

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
        .padding(.vertical, 2)
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

    private var tint: Color {
        if balance.total > 0 { .green }
        else if balance.total < 0 { .red }
        else { .secondary }
    }
}

private struct ReimbursementRow: View {
    let index: Int
    let reimbursement: Reimbursement
    let from: Participant?
    let to: Participant?
    let formatter: MoneyFormatter
    let onSettle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveHStack {
                Text("\(from?.name ?? "—") owes \(to?.name ?? "—")")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.Balances.reimbursement(index))

                Text(formatter.string(minorUnits: reimbursement.amount))
                    .fontWeight(.semibold)
                    .monospacedDigit()
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
