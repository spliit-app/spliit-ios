import SpliitAPI
import SpliitCore
import SwiftUI

/// What has happened to a group and when: expenses created, edited and deleted, and the times
/// the group's own settings changed.
///
/// The only screen that reads history rather than state, and so the only one that shows lines
/// about things which no longer exist. A deleted expense keeps its row, under the title it had
/// at the time, and simply has nowhere to lead — which is the whole reason to keep a log.
///
/// Pushed from the information tab rather than being a tab of its own. Four tabs and a search
/// capsule already fill the bar, and of the group's screens this is the one you consult rather
/// than work in — the information tab is where the other things you look up but do not edit
/// already live.
///
/// Who did what is the server's to know and it only knows what a client told it. Every mutating
/// procedure takes an optional `participantId` and nothing requires one, so a group edited from
/// the web app by someone who never said who they were reads "Someone" here — accurately.
struct ActivityLogView: View {

    @Environment(AppModel.self) private var app

    /// The instance this group is on. Every request from this screen goes through it: a group ID
    /// only means anything to the server that issued it.
    private var client: TRPCClient { app.client(forGroup: model.groupID) }
    let model: GroupDetailModel

    /// The expense a row opened, if any. Held here rather than handed up to `GroupDetailView`:
    /// this screen is pushed over that one, and a sheet presented from a view that is no longer
    /// the visible one is a sheet that may never appear.
    @State private var editingExpense: EditedExpense?

    /// `sheet(item:)` needs something `Identifiable`, and an expense ID is a bare `String`.
    private struct EditedExpense: Identifiable {
        let id: String
    }

    var body: some View {
        content
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            // The log is fetched here rather than with the rest of the group: it is the one
            // thing no other screen needs. `.task` runs when this is first built, and the model
            // ignores every call after the first that succeeded.
            .task { await model.loadActivitiesIfNeeded(using: client) }
            .sheet(item: $editingExpense) { edited in
                if let group = model.group {
                    ExpenseFormView(
                        mode: .edit(edited.id),
                        group: group,
                        categories: model.categories,
                        draft: nil,
                        onFinished: { await model.reloadAfterExpenseChange(using: client) }
                    )
                }
            }
            .trackScreen(.groupActivity)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingActivities {
            ProgressView().controlSize(.large)
        } else if model.didFailToLoad || model.didFailToLoadActivities {
            EmptyState(
                art: .icon("wifi.exclamationmark"),
                title: Text(errorTitle),
                description: Text(
                    model.activitiesFailure ?? String(localized: "The server didn’t respond.")
                )
            ) {
                Button("Try again") {
                    Task { await model.retryActivities(using: client) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.ActivityLog.retryButton)
            }
        // The sections rather than the raw list: a log made entirely of entries this version
        // cannot describe has nothing to draw, and an empty state reads better than a blank one.
        } else if model.activitySections.isEmpty {
            EmptyState(
                art: .icon("clock.arrow.circlepath"),
                title: Text("No activity yet"),
                description: Text("Adding, editing or deleting an expense is recorded here, and so is a change to the group itself.")
            )
        } else {
            list
        }
    }

    /// The group can arrive and its log still fail, so name whichever one is missing.
    private var errorTitle: LocalizedStringKey {
        model.didFailToLoad ? "Couldn’t load this group" : "Couldn’t load the activity"
    }

    private var list: some View {
        List {
            ForEach(model.activitySections, id: \.group) { section in
                Section {
                    ForEach(section.activities) { activity in
                        row(for: activity, in: section.group)
                    }
                } header: {
                    DateBucketHeader(title: section.group.title)
                }
            }

            if model.hasMoreActivities {
                HStack {
                    Spacer()
                    ProgressView()
                        .accessibilityLabel(Text("Loading more activity"))
                    Spacer()
                }
                .task { await model.loadNextActivityPage(using: client) }
            }
        }
        .refreshable { await model.refreshActivities(using: client) }
    }

    /// A row leads to its expense when there is still one to lead to. Rows about a deleted
    /// expense, and about the group's own settings, are text and stay text — an inert row is
    /// better than one that opens an editor for something that is gone.
    @ViewBuilder
    private func row(for activity: Activity, in bucket: ActivityDateGroup) -> some View {
        let opensExpense = activity.expenseStillExists && activity.expenseId != nil
        let content = ActivityRow(
            activity: activity,
            participantName: activity.participantId.flatMap { model.participant($0)?.name },
            showsDate: bucket.needsDate,
            opensExpense: opensExpense
        )

        if opensExpense, let expenseID = activity.expenseId {
            Button { editingExpense = EditedExpense(id: expenseID) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// One line of the log: what happened, and when.
private struct ActivityRow: View {

    let activity: Activity
    /// Whoever did it, already resolved against the group. Nil when the client that made the
    /// change did not say — which is what "Someone" below is for.
    let participantName: String?
    /// Whether the heading above has already said which day this was.
    let showsDate: Bool
    /// Whether this row leads to the expense it describes — false once that expense is gone,
    /// and for the rows about the group's own settings.
    let opensExpense: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
                // A fixed column so the sentences line up down the list rather than shifting
                // with the width of each glyph.
                .frame(width: 16)
                // Whatever the glyph says, the sentence beside it already said.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(.subheadline)
                    .accessibilityIdentifier(AccessibilityID.ActivityLog.entry(activity.id))
                    // Only where there is something to open: a hint on every row would promise
                    // a destination for the ones whose expense has been deleted. The empty
                    // branch is `verbatim` so that "" is not extracted as a string to translate.
                    .accessibilityHint(
                        opensExpense
                            ? Text("Opens this expense for editing")
                            : Text(verbatim: "")
                    )

                Text(timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.ActivityLog.time(activity.id))
            }
            // Fills the row, so the whole width is the tap target rather than just the words.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }

    /// The same glyphs the app uses for these actions elsewhere: `plus` adds an expense,
    /// `pencil` edits, `trash` deletes, and the group's own settings are a gear.
    private var symbol: String {
        switch activity.activityType {
        case .createExpense: "plus"
        case .updateExpense: "pencil"
        case .deleteExpense: "trash"
        case .updateGroup: "gearshape"
        case .unknown: "questionmark"
        }
    }

    /// The whole sentence, interpolated rather than assembled: word order and the place a name
    /// sits in it are the translation's business.
    private var summary: String {
        let who = participantName ?? String(localized: "Someone")
        // The title as it was when this was recorded, which is the point — renaming an expense
        // leaves the old name on the line describing its creation.
        let what = activity.title ?? ""

        return switch activity.activityType {
        case .createExpense: String(localized: "\(who) added “\(what)”.")
        case .updateExpense: String(localized: "\(who) updated “\(what)”.")
        case .deleteExpense: String(localized: "\(who) deleted “\(what)”.")
        case .updateGroup: String(localized: "\(who) changed the group settings.")
        // Never drawn: `GroupDetailModel.activitySections` leaves out the kinds this version
        // has no sentence for, rather than inventing one for them here.
        case .unknown: ""
        }
    }

    /// The time, plus the date when the heading above has not already given it. Both are left
    /// to Foundation, which knows how the reader's locale writes them.
    private var timestamp: String {
        showsDate
            ? activity.time.formatted(date: .abbreviated, time: .shortened)
            : activity.time.formatted(date: .omitted, time: .shortened)
    }
}

extension ActivityDateGroup {
    /// Section headings for the log.
    ///
    /// A `String` rather than a `LocalizedStringKey`, for the reason `DateBucketHeader`
    /// documents: it uppercases what it draws, and an accessibility label passed as `Text`
    /// comes back uppercased along with it.
    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .earlierThisWeek: String(localized: "Earlier this week")
        case .lastWeek: String(localized: "Last week")
        case .earlierThisMonth: String(localized: "Earlier this month")
        case .lastMonth: String(localized: "Last month")
        case .earlierThisYear: String(localized: "Earlier this year")
        case .lastYear: String(localized: "Last year")
        case .older: String(localized: "Older")
        }
    }
}
