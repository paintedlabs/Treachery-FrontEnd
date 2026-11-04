import Foundation
@testable import Treachery_iOS

/// Stands in for `AuthViewModel.retryProfileSetup()`: counts the retries,
/// and can run a hook while one is in flight, so a test can look at a screen
/// meanwhile, tap Try Again again, or cancel the retry.
@MainActor
final class ProfileSetupRetrySpy {
    private(set) var retryCount = 0
    /// Runs once inside a retry, while the setup attempt is in flight.
    var whileRetrying: (@MainActor () async -> Void)?

    func retry() async {
        retryCount += 1
        if let inFlight = whileRetrying {
            // One-shot, so a test can't recurse into it by accident.
            whileRetrying = nil
            await inFlight()
        }
    }
}
