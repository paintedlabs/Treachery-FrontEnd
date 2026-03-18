//
//  AddEditDeckView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/18/26.
//

import SwiftUI

struct AddEditDeckView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let existingDeck: Deck?
    var onSave: ((Deck) -> Void)?

    @State private var deckName: String
    @State private var commanderName: String
    @State private var hasPartner: Bool
    @State private var partnerCommanderName: String
    @State private var colorIdentity: [ManaColor]
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private let firestoreManager = FirestoreManager()

    private var isEditing: Bool { existingDeck != nil }

    private var isValid: Bool {
        !deckName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !commanderName.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!hasPartner || !partnerCommanderName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    init(deck: Deck? = nil, onSave: ((Deck) -> Void)? = nil) {
        self.existingDeck = deck
        self.onSave = onSave
        _deckName = State(initialValue: deck?.name ?? "")
        _commanderName = State(initialValue: deck?.commanderName ?? "")
        _hasPartner = State(initialValue: deck?.partnerCommanderName != nil)
        _partnerCommanderName = State(initialValue: deck?.partnerCommanderName ?? "")
        _colorIdentity = State(initialValue: deck?.colorIdentity ?? [])
    }

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Deck info card
                    VStack(spacing: 16) {
                        MtgSectionHeader(title: isEditing ? "Edit Deck" : "New Deck")

                        OrnateDivider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Deck Name")
                                .font(.caption)
                                .foregroundStyle(Color.mtgTextSecondary)
                            MtgTextField(
                                placeholder: "e.g. Eldrazi Ramp",
                                text: $deckName,
                                autocapitalization: .words
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Commander")
                                .font(.caption)
                                .foregroundStyle(Color.mtgTextSecondary)
                            MtgTextField(
                                placeholder: "e.g. Kozilek, the Great Distortion",
                                text: $commanderName,
                                autocapitalization: .words
                            )
                        }

                        Toggle("Has Partner Commander", isOn: $hasPartner.animation(.easeInOut(duration: 0.2)))
                            .foregroundStyle(Color.mtgTextPrimary)
                            .tint(Color.mtgGold)

                        if hasPartner {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Partner Commander")
                                    .font(.caption)
                                    .foregroundStyle(Color.mtgTextSecondary)
                                MtgTextField(
                                    placeholder: "e.g. Thrasios, Triton Hero",
                                    text: $partnerCommanderName,
                                    autocapitalization: .words
                                )
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(16)
                    .mtgCardFrame()

                    // Color identity card
                    VStack(spacing: 16) {
                        MtgSectionHeader(title: "Color Identity")

                        OrnateDivider()

                        ColorIdentitySelector(selectedColors: $colorIdentity)
                    }
                    .padding(16)
                    .mtgCardFrame()

                    if let error = errorMessage {
                        MtgErrorBanner(message: error)
                    }

                    // Save button
                    Button {
                        Task { await saveDeck() }
                    } label: {
                        if isSaving {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.mtgBackground)
                                Text("Saving...")
                            }
                        } else {
                            Text(isEditing ? "Save Changes" : "Add Deck")
                        }
                    }
                    .buttonStyle(MtgPrimaryButtonStyle(isDisabled: !isValid || isSaving))
                    .disabled(!isValid || isSaving)

                    // Delete button (edit mode only)
                    if isEditing {
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            if isDeleting {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.mtgError)
                                    Text("Deleting...")
                                }
                            } else {
                                Text("Delete Deck")
                            }
                        }
                        .foregroundStyle(Color.mtgError)
                        .disabled(isDeleting)
                        .confirmationDialog(
                            "Delete this deck?",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) {
                                Task { await deleteDeck() }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will permanently remove \"\(deckName)\" and its history association. This cannot be undone.")
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(isEditing ? "Edit Deck" : "New Deck")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Actions

    private func saveDeck() async {
        guard let userId = authViewModel.currentUserId else { return }
        guard isValid else { return }
        isSaving = true
        errorMessage = nil

        let deck = Deck(
            id: existingDeck?.id ?? UUID().uuidString,
            userId: userId,
            name: deckName.trimmingCharacters(in: .whitespaces),
            commanderName: commanderName.trimmingCharacters(in: .whitespaces),
            partnerCommanderName: hasPartner ? partnerCommanderName.trimmingCharacters(in: .whitespaces) : nil,
            colorIdentity: colorIdentity,
            createdAt: existingDeck?.createdAt ?? Date(),
            lastPlayedAt: existingDeck?.lastPlayedAt
        )

        do {
            if isEditing {
                try await firestoreManager.updateDeck(deck)
            } else {
                try await firestoreManager.createDeck(deck)
            }
            onSave?(deck)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteDeck() async {
        guard let deck = existingDeck else { return }
        isDeleting = true
        errorMessage = nil

        do {
            try await firestoreManager.deleteDeck(id: deck.id, userId: deck.userId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }
}

#if DEBUG
#Preview("Add Deck") {
    NavigationStack {
        AddEditDeckView()
    }
    .environmentObject(AuthViewModel())
}

#Preview("Edit Deck") {
    NavigationStack {
        AddEditDeckView(deck: Deck(
            id: "deck1",
            userId: "user1",
            name: "Eldrazi Ramp",
            commanderName: "Kozilek, the Great Distortion",
            partnerCommanderName: nil,
            colorIdentity: [.colorless],
            createdAt: Date(),
            lastPlayedAt: Date()
        ))
    }
    .environmentObject(AuthViewModel())
}
#endif
