import Foundation

/// Holds a mocked async call open until the test releases it, so the test can
/// act while the call is in flight (a repeat tap, a snapshot arriving) without
/// sleeping or yielding and hoping the scheduler cooperates.
///
/// Only the first call is held. Any later one, or one after `release()`,
/// carries straight on, so a test asserting there's no second call fails on
/// that assertion when there is one, instead of hanging.
@MainActor
final class CallGate {
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var heldCall: CheckedContinuation<Void, Never>?
    private var isReleased = false

    /// How many calls have reached the gate.
    private(set) var arrivals = 0

    /// Called by a mock: counts the call and, if it's the first, suspends it
    /// until `release()`.
    func hold() async {
        arrivals += 1
        resumeArrivalWaiters()
        guard arrivals == 1, !isReleased else { return }
        await withCheckedContinuation { heldCall = $0 }
    }

    /// Returns once a call has reached the gate, or once `task` has finished
    /// without making one. The test's own expectations then report that,
    /// rather than the test waiting forever.
    func waitForCall<Success>(from task: Task<Success, Never>) async {
        guard arrivals == 0 else { return }
        // Runs on the main actor once this has suspended, so the waiter is
        // registered before the task's end can resume it.
        Task {
            _ = await task.value
            resumeArrivalWaiters()
        }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    /// Lets the held call, and any later one, carry on.
    func release() {
        isReleased = true
        heldCall?.resume()
        heldCall = nil
    }

    private func resumeArrivalWaiters() {
        let waiters = arrivalWaiters
        arrivalWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
