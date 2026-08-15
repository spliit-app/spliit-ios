import Testing

@testable import SpliitCore

/// The point of this type is one distinction: an empty result that arrived, versus one that
/// hasn't. Every case below is a moment where a screen would otherwise claim a group has no
/// expenses when it has no idea yet.
@Suite("Load state")
struct LoadStateTests {

    @Test("Nothing is known before the first request starts")
    func initiallyAwaitingResult() {
        let state = LoadState()
        #expect(state.isAwaitingFirstResult)
        #expect(!state.hasLoaded)
        #expect(!state.failedWithNothingToShow)
    }

    @Test("A request in flight is still awaiting its first result")
    func loadingAwaitsResult() {
        var state = LoadState()
        state.begin()
        #expect(state.isLoading)
        #expect(state.isAwaitingFirstResult)
    }

    @Test("A success means an empty result can be trusted")
    func successStopsAwaiting() {
        var state = LoadState()
        state.begin()
        state.succeeded()
        #expect(!state.isLoading)
        #expect(state.hasLoaded)
        #expect(!state.isAwaitingFirstResult)
        #expect(!state.failedWithNothingToShow)
    }

    @Test("A first failure has nothing to fall back on")
    func failureWithNothingLoaded() {
        var state = LoadState()
        state.begin()
        state.failed("The server didn’t respond.")
        #expect(!state.isAwaitingFirstResult)
        #expect(state.failedWithNothingToShow)
        #expect(state.failure == "The server didn’t respond.")
    }

    @Test("A failed refresh keeps what was already loaded")
    func failureAfterSuccess() {
        var state = LoadState()
        state.begin()
        state.succeeded()
        state.begin()
        state.failed("Offline.")
        #expect(state.didFail)
        #expect(state.hasLoaded)
        // The list stays on screen with a warning, rather than being replaced by an error.
        #expect(!state.failedWithNothingToShow)
        #expect(!state.isAwaitingFirstResult)
    }

    @Test("Retrying after a failure goes back to not knowing")
    func retryClearsFailure() {
        var state = LoadState()
        state.begin()
        state.failed("Offline.")
        state.begin()
        #expect(state.isAwaitingFirstResult)
        #expect(!state.failedWithNothingToShow)
        #expect(state.failure == nil)
    }

    @Test("A success clears an earlier failure")
    func successClearsFailure() {
        var state = LoadState()
        state.begin()
        state.failed("Offline.")
        state.begin()
        state.succeeded()
        #expect(!state.didFail)
        #expect(state.failure == nil)
    }
}
