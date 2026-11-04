import Foundation

/// Spy for VoiceOver announcements: records what was said, in order.
final class AnnouncementSpy {
    private(set) var announcements: [String] = []

    func record(_ message: String) {
        announcements.append(message)
    }
}
