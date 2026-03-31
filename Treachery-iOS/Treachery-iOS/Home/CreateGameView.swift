//
//  CreateGameView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/13/26.
//

import SwiftUI

struct CreateGameView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var navigationPath: NavigationPath
    @StateObject private var viewModel = CreateGameViewModel()

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Game Mode selector
                    VStack(spacing: 8) {
                        MtgSectionHeader(title: "Game Mode")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("Game Mode", selection: $viewModel.gameMode) {
                            ForEach(GameMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)

                    if viewModel.gameMode.includesPlanechase {
                        Toggle("I have my own planar deck", isOn: $viewModel.useOwnDeck)
                            .foregroundStyle(Color.mtgTextPrimary)
                            .tint(Color.mtgGold)
                            .padding(.horizontal)
                    }

                    // Game settings card
                    VStack(spacing: 20) {
                        MtgSectionHeader(title: "Game Settings")

                        OrnateDivider()

                        Stepper("Starting Life: \(viewModel.startingLife)", value: $viewModel.startingLife, in: 20...60, step: 5)
                            .foregroundStyle(Color.mtgTextPrimary)
                            .accessibilityValue("\(viewModel.startingLife) life")
                    }
                    .padding(16)
                    .mtgCardFrame()

                    if let error = viewModel.errorMessage {
                        MtgErrorBanner(message: error)
                    }

                    Button {
                        Task {
                            guard let userId = authViewModel.currentUserId else { return }
                            if let destination = await viewModel.createGame(userId: userId) {
                                navigationPath.append(destination)
                            }
                        }
                    } label: {
                        if viewModel.isCreating {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.mtgBackground)
                                Text("Creating...")
                            }
                        } else {
                            Text("Create Game")
                        }
                    }
                    .buttonStyle(MtgPrimaryButtonStyle(isDisabled: viewModel.isCreating))
                    .disabled(viewModel.isCreating)
                    .accessibilityLabel(viewModel.isCreating ? "Creating game" : "Create game")
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { AnalyticsService.trackScreen("CreateGame") }
        .onChange(of: viewModel.gameMode) { _, _ in
            viewModel.resetOwnDeckIfNeeded()
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CreateGameView(navigationPath: .preview)
    }
    .environmentObject(AuthViewModel())
}
#endif
