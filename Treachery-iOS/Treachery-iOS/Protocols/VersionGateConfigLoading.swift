import Foundation

/// Reads `config/ios` for the version gate.
///
/// Implementations don't have to honor cancellation, because Firestore can't
/// cancel a one-shot read. The gate stops waiting at its own timeout, or at
/// once if the check is cancelled, whether or not the read stops.
protocol VersionGateConfigLoading: Sendable {
    /// Returns the config, or nil when the document doesn't exist.
    func loadConfig() async throws -> VersionGateConfig?
}
