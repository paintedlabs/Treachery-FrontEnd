//
//  DeckPickerView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/18/26.
//

import SwiftUI

struct DeckPickerView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let onSelect: (Deck?) -> Void

    @State private var decks: [Deck] = []
    @State private var isLoading = true
    @State private var showAddDeck = false
    @State private var errorMessage: String?

    private let firestoreManager = FirestoreManager()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtgBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading decks...")
                        .tint(Color.mtgGold)
                        .foregroundStyle(Color.mtgTextSecondary)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // No deck option
                            Button {
                                onSelect(nil)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(Color.mtgTextSecondary)
                                    Text("No Deck")
                                        .foregroundStyle(Color.mtgTextPrimary)
                                    Spacer()
                                }
                                .padding(16)
                            }
                            .mtgCardFrame(borderColor: Color.mtgDivider)
                            .padding(.horizontal)
                            .padding(.top)

                            if let error = errorMessage {
                                MtgErrorBanner(message: error)
                                    .padding()
                            }

                            // Deck list
                            ForEach(decks) { deck in
                                Button {
                                    onSelect(deck)
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(deck.name)
                                                .font(.system(.headline, design: .serif))
                                                .foregroundStyle(Color.mtgTextPrimary)
                                            Text(deck.commanderDisplayName)
                                                .font(.caption)
                                                .foregroundStyle(Color.mtgGold)
                                        }

                                        Spacer()

                                        if !deck.colorIdentity.isEmpty {
                                            ColorIdentityPips(colors: deck.colorIdentity)
                                        }
                                    }
                                    .padding(16)
                                }
                                .mtgCardFrame()
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }

                            // Add new deck
                            Button {
                                showAddDeck = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.mtgGold)
                                    Text("Add New Deck")
                                        .foregroundStyle(Color.mtgGold)
                                    Spacer()
                                }
                                .padding(16)
                            }
                            .mtgCardFrame(borderColor: Color.mtgGold.opacity(0.5))
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom)
                        }
                    }
                }
            }
            .navigationTitle("Select Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.mtgGold)
                }
            }
            .sheet(isPresented: $showAddDeck) {
                NavigationStack {
                    AddEditDeckView(onSave: { newDeck in
                        onSelect(newDeck)
                        dismiss()
                    })
                }
            }
            .task {
                await loadDecks()
            }
        }
    }

    private func loadDecks() async {
        guard let userId = authViewModel.currentUserId else { return }
        isLoading = true
        do {
            decks = try await firestoreManager.getDecks(forUserId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#if DEBUG
#Preview {
    DeckPickerView { deck in
        print("Selected: \(deck?.name ?? "None")")
    }
    .environmentObject(AuthViewModel())
}
#endif
