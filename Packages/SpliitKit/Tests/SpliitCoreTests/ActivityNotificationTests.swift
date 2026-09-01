import Foundation
import SpliitAPI
import Testing

@testable import SpliitCore

/// The rules behind what reaches a lock screen. None of this needs a server, a simulator or a
/// clock — which is the whole reason the planner is a pure function sitting apart from the
/// fetching.
@Suite("Activity notifications")
struct ActivityNotificationTests {

    private let me = "me"
    private let someoneElse = "them"
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func activity(
        _ id: String,
        _ type: ActivityType,
        at offset: TimeInterval,
        by participant: String? = nil,
        expense: String? = "expense-1",
        stillExists: Bool = true
    ) -> Activity {
        Activity(
            id: id,
            groupId: "group",
            time: start.addingTimeInterval(offset),
            activityType: type,
            participantId: participant,
            expenseId: expense,
            title: "Dinner",
            expenseStillExists: expense != nil && stillExists
        )
    }

    // MARK: - Where a group starts from

    @Test("A group that has never been looked at announces nothing, and remembers where it was")
    func firstRunIsSilent() {
        let log = [
            activity("a", .createExpense, at: -3600, by: someoneElse),
            activity("b", .updateExpense, at: -60, by: someoneElse),
        ]

        let plan = ActivityNotificationPlanner.plan(
            activities: log, since: nil, level: .everything, me: me
        )

        #expect(plan.certain.isEmpty)
        #expect(plan.needsExpenseLookup.isEmpty)
        #expect(plan.watermark == start.addingTimeInterval(-60))
    }

    @Test("A group with no activity at all still gets a watermark, so the next one counts")
    func firstRunWithEmptyLog() {
        let now = start.addingTimeInterval(500)

        let plan = ActivityNotificationPlanner.plan(
            activities: [], since: nil, level: .everything, me: me, now: now
        )

        #expect(plan.watermark == now)
    }

    @Test("The watermark never moves backwards")
    func watermarkOnlyGoesForward() {
        let plan = ActivityNotificationPlanner.plan(
            activities: [activity("a", .createExpense, at: -3600, by: someoneElse)],
            since: start,
            level: .everything,
            me: me
        )

        #expect(plan.certain.isEmpty)
        #expect(plan.watermark == start)
    }

    // MARK: - Everything

    @Test("Everything tells you about everything newer than the watermark, oldest first")
    func everythingIsOrderedOldestFirst() {
        let log = [
            activity("new", .createExpense, at: 120, by: someoneElse),
            activity("old", .updateGroup, at: 60, by: someoneElse, expense: nil),
            activity("seen", .createExpense, at: -60, by: someoneElse),
        ]

        let plan = ActivityNotificationPlanner.plan(
            activities: log, since: start, level: .everything, me: me
        )

        #expect(plan.certain.map(\.id) == ["old", "new"])
        #expect(plan.needsExpenseLookup.isEmpty)
        #expect(plan.watermark == start.addingTimeInterval(120))
    }

    @Test("Your own doing is never news, at any level", arguments: [
        NotificationLevel.everything, .involvingMe,
    ])
    func ownActivitiesAreSilent(level: NotificationLevel) {
        let plan = ActivityNotificationPlanner.plan(
            activities: [activity("mine", .createExpense, at: 60, by: me)],
            since: start,
            level: level,
            me: me
        )

        #expect(plan.certain.isEmpty)
        #expect(plan.needsExpenseLookup.isEmpty)
    }

    @Test("A kind this version has no sentence for interrupts nobody")
    func unknownKindsAreSilent() {
        let plan = ActivityNotificationPlanner.plan(
            activities: [activity("x", .unknown("SETTLED_UP"), at: 60, by: someoneElse)],
            since: start,
            level: .everything,
            me: me
        )

        #expect(plan.certain.isEmpty)
    }

    @Test("Nothing says nothing, but still keeps its place in the log")
    func nothingStillAdvances() {
        let plan = ActivityNotificationPlanner.plan(
            activities: [activity("a", .createExpense, at: 60, by: someoneElse)],
            since: start,
            level: .nothing,
            me: me
        )

        #expect(plan.certain.isEmpty)
        #expect(plan.needsExpenseLookup.isEmpty)
        #expect(plan.watermark == start.addingTimeInterval(60))
    }

    // MARK: - Only what involves me

    @Test("A change to the group itself lands on everybody, so it is not about you")
    func involvingMeIgnoresGroupEdits() {
        let plan = ActivityNotificationPlanner.plan(
            activities: [
                activity("g", .updateGroup, at: 60, by: someoneElse, expense: nil)
            ],
            since: start,
            level: .involvingMe,
            me: me
        )

        #expect(plan.certain.isEmpty)
        #expect(plan.needsExpenseLookup.isEmpty)
    }

    @Test("An expense that still exists has to be read before anything can be said about it")
    func involvingMeDefersToTheExpense() {
        let log = [
            activity("c", .createExpense, at: 60, by: someoneElse),
            activity("u", .updateExpense, at: 120, by: someoneElse, expense: "expense-2"),
        ]

        let plan = ActivityNotificationPlanner.plan(
            activities: log, since: start, level: .involvingMe, me: me
        )

        #expect(plan.certain.isEmpty)
        #expect(plan.needsExpenseLookup.map(\.id) == ["c", "u"])
    }

    /// The one place the narrow level deliberately over-tells. `paidFor` is gone with the row,
    /// so the alternative is never hearing that an expense which *was* yours has been removed.
    @Test("A deleted expense cannot be checked, so it is mentioned rather than dropped")
    func involvingMeTellsAboutDeletions() {
        let plan = ActivityNotificationPlanner.plan(
            activities: [
                activity("d", .deleteExpense, at: 60, by: someoneElse, stillExists: false)
            ],
            since: start,
            level: .involvingMe,
            me: me
        )

        #expect(plan.certain.map(\.id) == ["d"])
        #expect(plan.needsExpenseLookup.isEmpty)
    }

    // MARK: - Levels resolving against who you are

    @Test("Without a participant to match against, the narrow level cannot narrow")
    func involvingMeWidensWithoutAnIdentity() {
        #expect(NotificationLevel.involvingMe.resolved(knowingWhoYouAre: false) == .everything)
        #expect(NotificationLevel.involvingMe.resolved(knowingWhoYouAre: true) == .involvingMe)
    }

    @Test("The other two levels mean the same thing either way", arguments: [
        NotificationLevel.everything, .nothing,
    ])
    func otherLevelsAreUnaffectedByIdentity(level: NotificationLevel) {
        #expect(level.resolved(knowingWhoYouAre: false) == level)
        #expect(level.resolved(knowingWhoYouAre: true) == level)
    }
}

/// The half that is remembered on disk: a group's own level, and how far its log has been read.
@Suite("Group notification preferences")
struct GroupNotificationPreferenceTests {

    private let participants = [Participant(id: "p1", name: "Ana")]

    @MainActor
    private func makeStore() -> RecentGroupsStore {
        let url = URL.temporaryDirectory
            .appending(path: "notification-tests-\(UUID().uuidString).json")
        let store = RecentGroupsStore(fileURL: url)
        store.replaceAll(with: [RecentGroup(groupId: "g", groupName: "Lisbon")])
        return store
    }

    @Test("A group with no level of its own follows the default")
    @MainActor
    func followsTheDefault() {
        let store = makeStore()
        store.setActiveParticipant(.participant("p1"), groupId: "g")

        #expect(store.notificationLevel(inGroup: "g") == nil)
        #expect(
            store.effectiveNotificationLevel(
                inGroup: "g", default: .involvingMe, participants: participants
            ) == .involvingMe
        )
    }

    @Test("A group's own level outranks the default, and can be taken back")
    @MainActor
    func groupLevelWins() {
        let store = makeStore()
        store.setActiveParticipant(.participant("p1"), groupId: "g")

        store.setNotificationLevel(.nothing, groupId: "g")
        #expect(
            store.effectiveNotificationLevel(
                inGroup: "g", default: .everything, participants: participants
            ) == .nothing
        )

        store.setNotificationLevel(nil, groupId: "g")
        #expect(
            store.effectiveNotificationLevel(
                inGroup: "g", default: .everything, participants: participants
            ) == .everything
        )
    }

    /// Both ways of having no participant to match against — never asked, and answered "Nobody"
    /// — widen the same way, which is what makes the rule one sentence in the UI.
    @Test("Nobody to match against widens the narrow level", arguments: [
        nil, ActiveParticipant.nobody,
    ])
    @MainActor
    func widensWithoutAParticipant(answer: ActiveParticipant?) {
        let store = makeStore()
        if let answer { store.setActiveParticipant(answer, groupId: "g") }

        #expect(
            store.effectiveNotificationLevel(
                inGroup: "g", default: .involvingMe, participants: participants
            ) == .everything
        )
    }

    @Test("A participant who has left the group is no longer somebody to match against")
    @MainActor
    func widensWhenTheParticipantIsGone() {
        let store = makeStore()
        store.setActiveParticipant(.participant("p1"), groupId: "g")

        #expect(
            store.effectiveNotificationLevel(
                inGroup: "g", default: .involvingMe, participants: []
            ) == .everything
        )
    }

    @Test("The watermark only ever moves forward")
    @MainActor
    func watermarkOnlyMovesForward() {
        let store = makeStore()
        let later = Date(timeIntervalSince1970: 2_000)

        store.markActivitySeen(upTo: later, groupId: "g")
        store.markActivitySeen(upTo: Date(timeIntervalSince1970: 1_000), groupId: "g")

        #expect(store.lastNotifiedActivity(inGroup: "g") == later)
    }

    @Test("Both settings survive a restart, and a list written before they existed still reads")
    @MainActor
    func persistence() throws {
        let url = URL.temporaryDirectory
            .appending(path: "notification-tests-\(UUID().uuidString).json")

        let store = RecentGroupsStore(fileURL: url)
        store.replaceAll(with: [RecentGroup(groupId: "g", groupName: "Lisbon")])
        store.setNotificationLevel(.everything, groupId: "g")
        store.markActivitySeen(upTo: Date(timeIntervalSince1970: 42), groupId: "g")

        let reloaded = RecentGroupsStore(fileURL: url)
        #expect(reloaded.notificationLevel(inGroup: "g") == .everything)
        #expect(reloaded.lastNotifiedActivity(inGroup: "g") == Date(timeIntervalSince1970: 42))

        // What the React Native app wrote, and what every release before this one wrote.
        let legacy = Data(#"[{"groupId":"g","groupName":"Lisbon"}]"#.utf8)
        let decoded = try JSONDecoder().decode([RecentGroup].self, from: legacy)
        #expect(decoded.first?.notificationLevel == nil)
        #expect(decoded.first?.lastNotifiedActivity == nil)
    }
}
