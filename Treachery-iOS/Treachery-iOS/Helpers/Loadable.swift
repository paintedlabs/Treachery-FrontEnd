//
//  Loadable.swift
//  Treachery-iOS
//

/// Something a screen loads, in exactly the states the screen can show: not
/// asked for yet, loading, loaded or failed. It replaces an `isLoading` flag,
/// an optional value and an error message, which let a screen show "No games
/// yet" beside the error that explained why there were none.
///
/// A reload keeps the value already shown, both while it runs and if it
/// fails, so a failed refresh leaves the last good content on screen instead
/// of blanking it. An empty state belongs only to a value that loaded.
enum Loadable<Value, Failure: Error> {
    /// Nothing has been asked for yet.
    case idle
    /// A load is running. `previous` is what an earlier load returned, if any.
    case loading(previous: Value?)
    /// The last load succeeded.
    case loaded(Value)
    /// The last load failed. `previous` is what an earlier load returned, if any.
    case failed(Failure, previous: Value?)
}

extension Loadable {
    /// The value to show: the one just loaded, or the one an earlier load
    /// returned while a reload runs or after it failed. Nil until a load
    /// succeeds.
    var value: Value? {
        switch self {
        case .idle: nil
        case .loading(let previous): previous
        case .loaded(let value): value
        case .failed(_, let previous): previous
        }
    }

    /// Why the last load failed, or nil if it didn't.
    var failure: Failure? {
        guard case .failed(let failure, _) = self else { return nil }
        return failure
    }

    /// Starts a load, keeping the value already shown.
    mutating func startLoading() {
        self = .loading(previous: value)
    }

    /// Ends a load in failure, keeping the value already shown.
    mutating func fail(with failure: Failure) {
        self = .failed(failure, previous: value)
    }

    /// Changes the value shown, wherever this state keeps it, without
    /// changing the state. Does nothing until a load has succeeded.
    mutating func updateValue(_ change: (inout Value) -> Void) {
        switch self {
        case .idle, .loading(previous: nil), .failed(_, previous: nil):
            return
        case .loading(previous: var value?):
            change(&value)
            self = .loading(previous: value)
        case .loaded(var value):
            change(&value)
            self = .loaded(value)
        case .failed(let failure, previous: var value?):
            change(&value)
            self = .failed(failure, previous: value)
        }
    }
}

extension Loadable: Equatable where Value: Equatable, Failure: Equatable {}
extension Loadable: Sendable where Value: Sendable, Failure: Sendable {}
