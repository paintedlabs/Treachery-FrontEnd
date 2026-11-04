import Foundation
@testable import Treachery_iOS

/// A scripted `config/ios` read for version-gate tests.
actor StubVersionGateConfigLoader: VersionGateConfigLoading {
    enum Behavior: Sendable {
        /// Answers at once. Nil means the document doesn't exist.
        case returns(VersionGateConfig?)
        /// Fails at once.
        case fails(any Error)
        /// Never answers; ends only when the read is cancelled.
        case hangs
        /// Answers only after `release()`, and ignores cancellation the way a
        /// real Firestore read does.
        case answersWhenReleased(VersionGateConfig?)
    }

    private(set) var loadCount = 0
    private var behavior: Behavior
    private var isReleased = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func setBehavior(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }

    func loadConfig() async throws -> VersionGateConfig? {
        loadCount += 1
        switch behavior {
        case .returns(let config):
            return config
        case .fails(let error):
            throw error
        case .hangs:
            // Nobody advances this clock, so the read waits until it's cancelled.
            try await TestClock().sleep(for: .seconds(60))
            return nil
        case .answersWhenReleased(let config):
            if !isReleased {
                await withCheckedContinuation { releaseWaiters.append($0) }
            }
            return config
        }
    }
}
