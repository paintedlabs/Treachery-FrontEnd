import Testing
@testable import Treachery_iOS

/// Which case a `Loadable` is in, for tests that check a screen's state
/// whose value isn't `Equatable`.
enum LoadablePhase: Equatable {
    case idle, loading, loaded, failed
}

extension Loadable {
    var phase: LoadablePhase {
        switch self {
        case .idle: .idle
        case .loading: .loading
        case .loaded: .loaded
        case .failed: .failed
        }
    }
}

@Suite("Loadable")
struct LoadableTests {

    typealias Names = Loadable<[String], UserFacingError>

    @Test func valueIsWhatTheLastSuccessfulLoadReturned() {
        #expect(Names.idle.value == nil)
        #expect(Names.loading(previous: nil).value == nil)
        #expect(Names.loading(previous: ["Ada"]).value == ["Ada"])
        #expect(Names.loaded(["Ada"]).value == ["Ada"])
        #expect(Names.failed(.offline, previous: nil).value == nil)
        #expect(Names.failed(.offline, previous: ["Ada"]).value == ["Ada"])
    }

    @Test func failureIsSetOnlyWhenTheLastLoadFailed() {
        #expect(Names.idle.failure == nil)
        #expect(Names.loading(previous: ["Ada"]).failure == nil)
        #expect(Names.loaded(["Ada"]).failure == nil)
        #expect(Names.failed(.offline, previous: ["Ada"]).failure == .offline)
    }

    @Test func firstLoadThatFailsHasNothingToShow() {
        var names = Names.idle

        names.startLoading()
        #expect(names == .loading(previous: nil))

        names.fail(with: .offline)
        #expect(names == .failed(.offline, previous: nil))
    }

    @Test func reloadKeepsTheValueWhileItRunsAndIfItFails() {
        var names = Names.loaded(["Ada"])

        names.startLoading()
        #expect(names == .loading(previous: ["Ada"]))

        names.fail(with: .timedOut)
        #expect(names == .failed(.timedOut, previous: ["Ada"]))

        // Retrying after a failure still keeps it.
        names.startLoading()
        #expect(names == .loading(previous: ["Ada"]))
    }

    @Test("updateValue changes the kept value and leaves the case alone", arguments: [
        (Names.loaded(["Ada"]), Names.loaded(["Ada", "Bob"])),
        (.loading(previous: ["Ada"]), .loading(previous: ["Ada", "Bob"])),
        (.failed(.offline, previous: ["Ada"]), .failed(.offline, previous: ["Ada", "Bob"])),
        (.idle, .idle),
        (.loading(previous: nil), .loading(previous: nil)),
        (.failed(.offline, previous: nil), .failed(.offline, previous: nil)),
    ])
    func updateValue(state: Names, expected: Names) {
        var names = state

        names.updateValue { $0.append("Bob") }

        #expect(names == expected)
    }
}
