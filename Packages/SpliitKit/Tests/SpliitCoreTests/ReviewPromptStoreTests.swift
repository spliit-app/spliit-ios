import Foundation
import Testing

@testable import SpliitCore

/// Every gate, from both sides. The whole value of this type is the asks it *doesn't* make, and
/// none of that is observable in the app — a wrongly opened gate looks exactly like a quiet one
/// until it ships.
@Suite("Review prompt")
@MainActor
struct ReviewPromptStoreTests {

    private static let day: TimeInterval = 24 * 3600
    private static let now = Date(timeIntervalSince1970: 1_767_225_600)

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "review-prompt-tests-\(UUID().uuidString)"))
    }

    /// A store that would ask, so a test can shut one gate at a time and see it stop.
    private func makeStore(
        _ defaults: UserDefaults,
        installedDaysAgo: Double = 30,
        activations: Int = 10,
        version: String = "2.2.0",
        at instant: Date = ReviewPromptStoreTests.now
    ) -> ReviewPromptStore {
        defaults.set(
            instant.addingTimeInterval(-installedDaysAgo * Self.day),
            forKey: ReviewPromptStore.Key.installDate
        )
        defaults.set(activations, forKey: ReviewPromptStore.Key.activationCount)
        return ReviewPromptStore(defaults: defaults, version: version, now: { instant })
    }

    private func isArmed(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: ReviewPromptStore.Key.isArmed)
    }

    // MARK: - Install age

    @Test("A milestone in the first fortnight arms nothing")
    func tooNewToAsk() throws {
        let defaults = try makeDefaults()
        makeStore(defaults, installedDaysAgo: 5).record(.groupSettledUp)

        #expect(!isArmed(defaults))
    }

    @Test("A milestone after a fortnight arms the ask")
    func oldEnoughToAsk() throws {
        let defaults = try makeDefaults()
        makeStore(defaults, installedDaysAgo: 15).record(.groupSettledUp)

        #expect(isArmed(defaults))
    }

    @Test("The install date is recorded once and never moved")
    func installDateIsSeededOnce() throws {
        let defaults = try makeDefaults()
        let planted = Self.now.addingTimeInterval(-90 * Self.day)
        defaults.set(planted, forKey: ReviewPromptStore.Key.installDate)

        _ = ReviewPromptStore(defaults: defaults, version: "2.2.0", now: { Self.now })

        #expect(defaults.object(forKey: ReviewPromptStore.Key.installDate) as? Date == planted)
    }

    @Test("A first launch records an install date to count from")
    func installDateIsSeededOnFirstLaunch() throws {
        let defaults = try makeDefaults()

        _ = ReviewPromptStore(defaults: defaults, version: "2.2.0", now: { Self.now })

        #expect(defaults.object(forKey: ReviewPromptStore.Key.installDate) as? Date == Self.now)
    }

    // MARK: - Activations

    @Test("Somebody who has barely opened the app is not asked")
    func tooFewActivations() throws {
        let defaults = try makeDefaults()
        makeStore(defaults, activations: 3).record(.groupSettledUp)

        #expect(!isArmed(defaults))
    }

    @Test("The seventh activation is enough")
    func enoughActivations() throws {
        let defaults = try makeDefaults()
        makeStore(defaults, activations: 7).record(.groupSettledUp)

        #expect(isArmed(defaults))
    }

    // MARK: - Once per version, and rarely even then

    @Test("A version that has already asked doesn’t ask again")
    func oncePerVersion() throws {
        let defaults = try makeDefaults()
        defaults.set("2.2.0", forKey: ReviewPromptStore.Key.lastAskedVersion)

        makeStore(defaults, version: "2.2.0").record(.groupSettledUp)

        #expect(!isArmed(defaults))
    }

    @Test("A release that hasn’t asked yet may, once the quiet period is over")
    func newVersionMayAskAgain() throws {
        let defaults = try makeDefaults()
        defaults.set("2.1.0", forKey: ReviewPromptStore.Key.lastAskedVersion)
        defaults.set(
            Self.now.addingTimeInterval(-200 * Self.day), forKey: ReviewPromptStore.Key.lastAskedAt
        )

        makeStore(defaults, version: "2.2.0").record(.groupSettledUp)

        #expect(isArmed(defaults))
    }

    @Test("A run of quick releases can’t turn into a run of prompts")
    func quietPeriodOutlastsAVersionBump() throws {
        let defaults = try makeDefaults()
        defaults.set("2.1.0", forKey: ReviewPromptStore.Key.lastAskedVersion)
        defaults.set(
            Self.now.addingTimeInterval(-30 * Self.day), forKey: ReviewPromptStore.Key.lastAskedAt
        )

        makeStore(defaults, version: "2.2.0").record(.groupSettledUp)

        #expect(!isArmed(defaults))
    }

    // MARK: - Expenses

    @Test("Recording expenses is a milestone at the twentieth, and only there")
    func expensesCountUpToOneMilestone() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults)

        for _ in 1...19 { store.record(.expenseRecorded) }
        #expect(!isArmed(defaults))

        store.record(.expenseRecorded)
        #expect(isArmed(defaults))

        defaults.set(false, forKey: ReviewPromptStore.Key.isArmed)
        for _ in 1...5 { store.record(.expenseRecorded) }
        #expect(!isArmed(defaults))
    }

    /// The gates decide whether to *ask*, not whether the expense happened. Dropping the count
    /// while they are shut would restart it every launch and the milestone would never arrive.
    @Test("Expenses recorded behind a shut gate still count towards the milestone")
    func expensesCountEvenWhenIneligible() throws {
        let defaults = try makeDefaults()
        makeStore(defaults, installedDaysAgo: 1).record(.expenseRecorded)

        #expect(defaults.integer(forKey: ReviewPromptStore.Key.expenseCount) == 1)
        #expect(!isArmed(defaults))
    }

    // MARK: - Activation

    @Test("An ordinary launch asks for nothing")
    func nothingArmedAsksNothing() throws {
        let defaults = try makeDefaults()

        #expect(makeStore(defaults).recordActivation() == false)
    }

    @Test("An armed ask fires on the next activation, and only that once")
    func armedAskFiresOnce() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults)
        store.record(.groupSettledUp)

        #expect(store.recordActivation() == true)
        #expect(!isArmed(defaults))
        #expect(store.recordActivation() == false)
    }

    @Test("Firing records the version and the day, so the next ask is gated on both")
    func firingRecordsWhatItAsked() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults, version: "2.2.0")
        store.record(.groupSettledUp)
        _ = store.recordActivation()

        #expect(defaults.string(forKey: ReviewPromptStore.Key.lastAskedVersion) == "2.2.0")
        #expect(defaults.object(forKey: ReviewPromptStore.Key.lastAskedAt) as? Date == Self.now)
    }

    @Test("Every activation is counted")
    func activationsAreCounted() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults, activations: 4)

        _ = store.recordActivation()
        _ = store.recordActivation()

        #expect(defaults.integer(forKey: ReviewPromptStore.Key.activationCount) == 6)
    }

    /// The point of arming rather than asking: the ask waits for a moment when the person is
    /// not in the middle of the thing that earned it.
    @Test("A milestone never asks by itself")
    func aMilestoneOnlyArms() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults)

        store.record(.groupSettledUp)

        #expect(isArmed(defaults))
        #expect(defaults.string(forKey: ReviewPromptStore.Key.lastAskedVersion) == nil)
    }
}
