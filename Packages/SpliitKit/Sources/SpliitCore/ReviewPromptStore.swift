import Foundation

/// Something that went well, and that the person is likely to have noticed happening.
///
/// Deliberately short. A milestone is not "the user did a thing" — it is a moment where the app
/// has just been useful, which is the only honest time to ask whether it is any good.
public enum ReviewMilestone: Sendable, Equatable {

    /// A payment was marked as paid and the group came out level. This is the app finishing the
    /// job it exists for, and the one moment in Spliit that reliably feels like an ending.
    case groupSettledUp

    /// An expense was recorded. On its own that is nothing; the store counts them, and the
    /// count is what eventually means "this is how I do this now".
    case expenseRecorded
}

/// Decides whether — and when — to ask for an App Store review.
///
/// An app with no marketing budget lives or dies on the reviews it is given, so it does have to
/// ask. What it must not do is ask badly, and every rule below exists to stop one specific way
/// of asking badly:
///
/// 1. **Ask only after something went well.** Never after a failed load, a deleted expense or a
///    refused form. ``ReviewMilestone`` is the whole list of moments that qualify.
/// 2. **Never interrupt.** A milestone only *arms* the ask — ``recordActivation()`` is what
///    fires it, on the next trip to the foreground, when the person is not in the middle of
///    anything. Somebody who just settled a group gets to enjoy that undisturbed.
/// 3. **Ask rarely.** Once per marketing version, and never twice inside ``quietPeriod``. iOS
///    itself caps this at three prompts a year and silently drops the rest, so an app that asks
///    too eagerly does not annoy people *and* get reviews — it annoys people and gets nothing.
/// 4. **Ask only someone who has actually used it.** ``minimumInstallAge`` and
///    ``minimumActivations`` between them exclude everybody still deciding.
/// 5. **Use the system prompt and nothing else.** No "do you like Spliit?" screen that sends
///    the happy answers to the App Store and the unhappy ones to a form. Apple forbids it, and
///    it is what makes a rating average a lie.
/// 6. **Leave a way in that is not an ask.** Settings carries a permanent link to the listing,
///    so someone who wants to say something never has to wait to be asked.
///
/// Nothing here leaves the device. The whole of it is a handful of `UserDefaults` values, and
/// no analytics event is sent when a prompt is armed or shown — see ``AnalyticsEvent`` for the
/// company that keeps.
@MainActor
public final class ReviewPromptStore {

    /// The stored state, in full. Public because the UI-test reset clears these by name, and
    /// because a test that asserts on the real keys cannot drift from the ones in use.
    public enum Key {
        public static let installDate = "reviewPrompt.installDate"
        public static let activationCount = "reviewPrompt.activationCount"
        public static let expenseCount = "reviewPrompt.expenseCount"
        public static let lastAskedVersion = "reviewPrompt.lastAskedVersion"
        public static let lastAskedAt = "reviewPrompt.lastAskedAt"
        public static let isArmed = "reviewPrompt.isArmed"

        public static let all = [
            installDate, activationCount, expenseCount, lastAskedVersion, lastAskedAt, isArmed,
        ]
    }

    /// How long the app has to have been on the phone. Long enough to cover a trip, which is
    /// the shape of use Spliit is usually installed for.
    public static let minimumInstallAge: TimeInterval = 14 * 24 * 3600

    /// How many times it has to have been brought to the front.
    public static let minimumActivations = 7

    /// The number of expenses at which recording one stops being a trial and starts being a
    /// habit. Only this exact count is a milestone: were it a threshold, every expense after it
    /// would re-arm an ask the person had already dismissed.
    public static let expensesWorthAskingAfter = 20

    /// How long the app says nothing at all after an ask, whatever ships in between.
    public static let quietPeriod: TimeInterval = 120 * 24 * 3600

    private let defaults: UserDefaults
    private let version: String
    private let now: () -> Date

    public init(
        defaults: UserDefaults = .standard,
        version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "",
        now: @escaping () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.version = version
        self.now = now

        // An install date we never recorded is one we cannot recover, so the first launch that
        // has this code is the beginning as far as it is concerned. Somebody who has had the
        // app for a year waits another fortnight, which is the conservative direction to be
        // wrong in.
        if defaults.object(forKey: Key.installDate) == nil {
            defaults.set(now(), forKey: Key.installDate)
        }
    }

    /// Counts this trip to the foreground, and answers whether the moment has come to ask.
    ///
    /// The answer is consumed: it is true once per armed milestone and false forever after,
    /// whatever the person then does with the dialog. Whether they wrote a review, dismissed it,
    /// or never saw it because iOS was rate-limiting is not something the app is told, and
    /// treating "we asked" as the fact we know is the only version that cannot ask twice.
    @discardableResult
    public func recordActivation() -> Bool {
        defaults.set(activationCount + 1, forKey: Key.activationCount)

        guard defaults.bool(forKey: Key.isArmed) else { return false }
        defaults.set(false, forKey: Key.isArmed)
        defaults.set(version, forKey: Key.lastAskedVersion)
        defaults.set(now(), forKey: Key.lastAskedAt)
        return true
    }

    /// Notes that something went well, and arms the ask if every gate is open.
    ///
    /// Safe to call on every occurrence: counting is this type's job, and a milestone that does
    /// not qualify is simply dropped.
    public func record(_ milestone: ReviewMilestone) {
        if milestone == .expenseRecorded {
            defaults.set(expenseCount + 1, forKey: Key.expenseCount)
        }
        guard isWorthAsking(after: milestone) else { return }
        defaults.set(true, forKey: Key.isArmed)
    }

    private func isWorthAsking(after milestone: ReviewMilestone) -> Bool {
        if milestone == .expenseRecorded, expenseCount != Self.expensesWorthAskingAfter {
            return false
        }

        guard let installDate = defaults.object(forKey: Key.installDate) as? Date,
              now().timeIntervalSince(installDate) >= Self.minimumInstallAge
        else {
            return false
        }

        guard activationCount >= Self.minimumActivations else { return false }
        guard defaults.string(forKey: Key.lastAskedVersion) != version else { return false }

        if let lastAsked = defaults.object(forKey: Key.lastAskedAt) as? Date,
           now().timeIntervalSince(lastAsked) < Self.quietPeriod {
            return false
        }

        return true
    }

    private var activationCount: Int { defaults.integer(forKey: Key.activationCount) }
    private var expenseCount: Int { defaults.integer(forKey: Key.expenseCount) }
}
