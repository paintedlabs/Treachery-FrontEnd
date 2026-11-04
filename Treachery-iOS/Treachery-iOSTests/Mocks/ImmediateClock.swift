import Foundation

/// A clock whose sleeps end straight away, for tests of code that waits on a
/// clock when the wait isn't what they test. Use `TestClock` when it is.
struct ImmediateClock: Clock {
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

    var now: Instant { Instant(offset: .zero) }

    var minimumResolution: Swift.Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Swift.Duration? = nil) async throws {
        try Task.checkCancellation()
    }
}
