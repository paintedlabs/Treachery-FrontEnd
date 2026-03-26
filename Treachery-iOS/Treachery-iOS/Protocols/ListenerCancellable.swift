import Foundation

/// Abstraction over FirebaseFirestore.ListenerRegistration so consumers
/// don't need to import FirebaseFirestore directly.
protocol ListenerCancellable {
    func remove()
}
