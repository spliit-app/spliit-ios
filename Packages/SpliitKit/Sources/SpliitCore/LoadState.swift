import Foundation

/// Where one request stands, so a screen can tell "there is nothing" apart from "nothing has
/// arrived yet".
///
/// A group screen loads several things at once — the group, its expenses, its balances — and
/// they finish in whatever order the server answers. An empty state driven by "this collection
/// is empty" alone therefore announces that a group has no expenses while the expenses are
/// still on the wire, and again if their request fails outright. Only a request that has
/// actually succeeded makes an empty collection mean anything.
public struct LoadState: Equatable, Sendable {

    public private(set) var isLoading = false

    /// A request has succeeded at least once, so an empty result really is empty.
    public private(set) var hasLoaded = false

    public private(set) var didFail = false

    /// Why the last attempt failed, ready to show.
    public private(set) var failure: String?

    public init() {}

    /// An attempt is under way; whatever the last one failed with no longer applies.
    public mutating func begin() {
        isLoading = true
        didFail = false
        failure = nil
    }

    public mutating func succeeded() {
        isLoading = false
        hasLoaded = true
        didFail = false
        failure = nil
    }

    public mutating func failed(_ message: String?) {
        isLoading = false
        didFail = true
        failure = message
    }

    /// Nothing has arrived and nothing has failed, so the result is not known yet. True before
    /// the first attempt even starts, which is exactly when a view is first laid out.
    public var isAwaitingFirstResult: Bool {
        !hasLoaded && !didFail
    }

    /// It failed, and there is no earlier success to keep showing.
    public var failedWithNothingToShow: Bool {
        didFail && !hasLoaded
    }
}
