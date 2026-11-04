//
//  DocumentEvent.swift
//  Treachery-iOS
//

import Foundation

/// What a document listener reports for each snapshot.
///
/// The outcomes stay apart because screens must treat them differently: a
/// deleted game ends the screen, a listener error gets Retry, and data this
/// build can't read asks for an update. Collapsing them into `nil` used to
/// make a decode failure look like a deleted game, and a game that was
/// already gone look like one still loading.
enum DocumentEvent<Value> {
    /// The document exists and decoded.
    case loaded(Value)
    /// The server confirmed the document doesn't exist: it was deleted or
    /// never created. A miss in the local cache alone is not reported.
    case missing
    /// Nothing usable arrived; the failure says why.
    case failed(ListenerFailure)
}

/// Why a listener delivered nothing usable.
enum ListenerFailure: Error {
    /// Firestore reported an error and stopped the listener. Nothing more
    /// arrives until it is attached again.
    case listenerStopped(any Error)
    /// Firestore refused the read. Only a game's players may read its player
    /// documents, so this most likely means the user is no longer in the
    /// game: they left, or never got a seat when it started. Attaching again
    /// would be refused again.
    case accessDenied(any Error)
    /// A document arrived that this build can't decode, most likely written
    /// by a newer server or client. Attaching again would read the same
    /// data, so retrying can't help; updating the app might.
    case unreadable(any Error)
}
