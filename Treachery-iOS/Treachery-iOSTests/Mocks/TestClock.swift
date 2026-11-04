import Foundation
import Synchronization

/// A clock that moves only when a test calls `advance(by:)`, so timeouts fire
/// on cue instead of after real waiting.
///
/// Call `waitForSleepers(count:)` before advancing: it returns once the code
/// under test is actually asleep on this clock, which removes the race between
/// "start the timer" and "move the clock".
final class TestClock: Clock {
    struct Instant: InstantProtocol {
        let offset: Swift.Duration

        func advanced(by duration: Swift.Duration) -> Self {
            Self(offset: offset + duration)
        }

        func duration(to other: Self) -> Swift.Duration {
            other.offset - offset
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct SleeperWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var nextSleeperID = 0
        var sleepers: [Int: Sleeper] = [:]
        var sleeperWaiters: [SleeperWaiter] = []
    }

    private enum Registration {
        case cancelled
        case due
        case asleep(wakingWaiters: [CheckedContinuation<Void, Never>])
    }

    private let lockedState = Mutex(State())

    var now: Instant {
        lockedState.withLock { $0.now }
    }

    var minimumResolution: Swift.Duration { .zero }

    /// When each sleeper still waiting will wake, as time since the clock
    /// started, earliest first. Sleepers leave this list when they wake or are
    /// cancelled, so tests can check a timeout's length and that it didn't
    /// fire early.
    var pendingDeadlines: [Swift.Duration] {
        lockedState.withLock { state in
            state.sleepers.values.map(\.deadline.offset).sorted()
        }
    }

    func sleep(until deadline: Instant, tolerance: Swift.Duration? = nil) async throws {
        let id = lockedState.withLock { state in
            state.nextSleeperID += 1
            return state.nextSleeperID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(id, deadline: deadline, continuation: continuation)
            }
        } onCancel: {
            let sleeper = lockedState.withLock { $0.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline has passed.
    func advance(by duration: Swift.Duration) {
        let due: [Sleeper] = lockedState.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let dueIDs = state.sleepers.filter { $0.value.deadline <= now }.map(\.key)
            return dueIDs.compactMap { state.sleepers.removeValue(forKey: $0) }
        }
        due.forEach { $0.continuation.resume() }
    }

    /// Returns once at least `count` sleepers are waiting on this clock.
    func waitForSleepers(count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isReady = lockedState.withLock { state in
                guard state.sleepers.count < count else { return true }
                state.sleeperWaiters.append(SleeperWaiter(count: count, continuation: continuation))
                return false
            }
            if isReady { continuation.resume() }
        }
    }

    // Checking for cancellation under the lock pairs with the onCancel
    // handler: whichever runs second sees the other's work, so a sleeper is
    // never left waiting after its task was cancelled.
    private func register(_ id: Int, deadline: Instant, continuation: CheckedContinuation<Void, any Error>) {
        let registration: Registration = lockedState.withLock { state in
            if Task.isCancelled { return .cancelled }
            if deadline <= state.now { return .due }
            state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
            let asleep = state.sleepers.count
            let ready = state.sleeperWaiters.filter { $0.count <= asleep }
            state.sleeperWaiters.removeAll { $0.count <= asleep }
            return .asleep(wakingWaiters: ready.map(\.continuation))
        }
        switch registration {
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        case .due:
            continuation.resume()
        case .asleep(let waiters):
            waiters.forEach { $0.resume() }
        }
    }
}
