//
//  HomeViewModel.swift
//  Treachery-iOS
//

import Foundation

@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: - Published State

    @Published var activeGame: Game?

    // MARK: - Properties

    private let firestoreManager: FirestoreManaging

    // MARK: - Init

    init(firestoreManager: FirestoreManaging = FirestoreManager()) {
        self.firestoreManager = firestoreManager
    }

    // MARK: - Active Game Check

    func checkForActiveGame(userId: String) async {
        do {
            activeGame = try await firestoreManager.getActiveGame(forUserId: userId)
        } catch {
            activeGame = nil
        }
    }
}
