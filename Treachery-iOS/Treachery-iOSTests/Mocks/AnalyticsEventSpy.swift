import Foundation

/// Spy for analytics: records event names in the order they were tracked.
final class AnalyticsEventSpy {
    private(set) var events: [String] = []

    func record(_ name: String) {
        events.append(name)
    }
}
