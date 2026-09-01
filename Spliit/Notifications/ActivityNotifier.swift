import Foundation
import SpliitAPI
import SpliitCore
import UserNotifications

/// Reads each remembered group's activity log and turns what is new into notifications.
///
/// This is the whole delivery mechanism. Spliit has no accounts and no server that has ever
/// heard of a phone, so there is nothing to register a push token with — the app polls, in the
/// background refreshes iOS grants it, and posts to itself. Everything that follows from that:
///
/// - **iOS decides when this runs**, and it is stingy about it with an app the user rarely
///   opens. A notification can be minutes late or hours late. Both screens that offer the
///   setting say so, because a feature that quietly under-delivers is worse than one that says
///   what it is.
/// - **A background run has a budget**, so this is deliberately frugal: a group whose level is
///   `.nothing` costs no request at all, and the expense lookups only happen for the narrow
///   level, only for what is actually new, and only when the expense still exists.
/// - **Nothing is posted twice.** A request identifier is the activity's own ID, so a run that
///   overlaps another replaces its notification rather than adding a second one.
///
/// The decisions are not here: `ActivityNotificationPlanner` has them, in `SpliitCore`, where a
/// suite can exercise them without a server or a simulator. This is the part that fetches.
@MainActor
struct ActivityNotifier {

    let settings: SettingsStore
    let recentGroups: RecentGroupsStore
    let client: TRPCClient
    var center: UNUserNotificationCenter = .current()

    /// How many lines a group is worth before they become a count. Four separate notifications
    /// from one group is a wall to swipe through; "4 new activities" is one line that says the
    /// same thing and opens the same place.
    private static let separateNotificationLimit = 3

    /// How far back a single run looks. A group busier than this between two refreshes gets the
    /// summary anyway, so a bigger page would only buy a more precise count.
    private static let pageSize = 20

    /// Carries the group to open when the notification is tapped. `nonisolated` because the
    /// delegate that reads it is: a tap is delivered wherever iOS feels like delivering it.
    nonisolated static let groupIDKey = "groupId"

    func run() async {
        // Asking rather than assuming: authorisation can be revoked in iOS Settings between two
        // runs, and posting into a void would still cost every request below.
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        for group in recentGroups.groups where !group.isArchived {
            // A background refresh is given seconds, not minutes, and iOS cancels the task when
            // they are up. Stopping here leaves the groups already dealt with recorded and the
            // rest exactly as they were, which is what the next refresh expects to find.
            if Task.isCancelled { return }
            await run(for: group)
        }
    }

    /// One group. Failures are silent on purpose — a background refresh has nobody to tell, and
    /// a group that could not be reached this time is simply read again on the next one, from
    /// the same watermark.
    private func run(for remembered: RecentGroup) async {
        let declared = remembered.notificationLevel ?? settings.notificationLevel
        // The branch that costs nothing at all.
        guard declared != .nothing else { return }

        guard
            let response = try? await client.call(
                Spliit.activities(groupId: remembered.groupId, limit: Self.pageSize)
            )
        else {
            return
        }

        // Nearly every group on nearly every refresh stops here, one request in. The group
        // itself is only worth fetching once there is something to say — it is needed for the
        // names in the sentences, and to know whether the participant this phone belongs to is
        // still in it.
        let seen = remembered.lastNotifiedActivity
        guard let seen, response.activities.contains(where: { $0.time > seen }) else {
            recentGroups.markActivitySeen(
                upTo: ActivityNotificationPlanner.watermark(
                    after: response.activities, since: seen
                ),
                groupId: remembered.groupId
            )
            return
        }

        guard let group = try? await client.call(Spliit.group(id: remembered.groupId)).group
        else {
            return
        }

        let me = ActiveParticipant
            .resolve(remembered.activeParticipant, in: group.participants)?.participantID

        let plan = ActivityNotificationPlanner.plan(
            activities: response.activities,
            since: seen,
            level: declared.resolved(knowingWhoYouAre: me != nil),
            me: me
        )

        var toPost = plan.certain
        for activity in plan.needsExpenseLookup {
            if await involvesMe(activity, me: me) { toPost.append(activity) }
        }
        toPost.sort { $0.time < $1.time }

        await post(toPost, in: group)
        recentGroups.markActivitySeen(upTo: plan.watermark, groupId: group.id)
    }

    /// Whether an expense has this person on it, either as the one who paid or as one of the
    /// people it was split between.
    ///
    /// `paidFor` is the answer and the activity log does not carry it — the `expense` sent
    /// beside each row is the expense record with no participants joined on — so it costs a
    /// request. An expense that cannot be read counts as involving you: the request usually
    /// fails because it has just been deleted or because the network went, and neither is a
    /// reason to decide, on your behalf, that money you may owe is not your business.
    private func involvesMe(_ activity: Activity, me: String?) async -> Bool {
        guard let me, let expenseID = activity.expenseId else { return true }
        guard
            let expense = try? await client.call(
                Spliit.expense(groupId: activity.groupId, expenseId: expenseID)
            ).expense
        else {
            return true
        }
        return expense.paidById == me || expense.paidFor.contains { $0.participantId == me }
    }

    private func post(_ activities: [Activity], in group: SpliitAPI.Group) async {
        guard !activities.isEmpty else { return }

        if activities.count > Self.separateNotificationLimit {
            guard let newest = activities.last else { return }
            await add(
                identifier: newest.id,
                body: String(localized: "\(activities.count) new activities."),
                in: group
            )
            return
        }

        let names = Dictionary(
            uniqueKeysWithValues: group.participants.map { ($0.id, $0.name) }
        )
        for activity in activities {
            await add(
                identifier: activity.id,
                body: ActivitySentence.text(
                    for: activity,
                    participantName: activity.participantId.flatMap { names[$0] }
                ),
                in: group
            )
        }
    }

    private func add(identifier: String, body: String, in group: SpliitAPI.Group) async {
        let content = UNMutableNotificationContent()
        // The group's name is the title because it is what tells two notifications apart on a
        // lock screen; the sentence below already says everything else.
        content.title = group.name
        content.body = body
        content.sound = .default
        // iOS stacks a thread's notifications into one entry, which is what keeps a busy group
        // from burying a quiet one.
        content.threadIdentifier = group.id
        content.userInfo = [Self.groupIDKey: group.id]

        // Keyed by the activity, so a run that overlaps another replaces rather than repeats.
        // A `nil` trigger delivers now.
        let request = UNNotificationRequest(
            identifier: "activity-\(identifier)", content: content, trigger: nil
        )
        try? await center.add(request)
    }
}
