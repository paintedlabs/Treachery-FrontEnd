//
//  JoinGameView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/13/26.
//

import SwiftUI

struct JoinGameView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var navigationPath: NavigationPath
    @StateObject private var viewModel = JoinGameViewModel()

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                // Game code entry card
                VStack(spacing: 16) {
                    MtgSectionHeader(title: "Enter Game Code")

                    OrnateDivider()

                    Text("Enter the 4-character game code")
                        .font(.subheadline)
                        .foregroundStyle(Color.mtgTextSecondary)

                    TextField("ABCD", text: $viewModel.gameCode)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .foregroundStyle(Color.mtgGoldBright)
                        .background(Color.mtgCardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.mtgGold, lineWidth: 1.5)
                        )
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Game code")
                        .accessibilityHint("Enter the 4-character code to join a game")
                        .onChange(of: viewModel.gameCode) { _, newValue in
                            viewModel.formatGameCode(newValue)
                        }
                }
                .padding(20)
                .mtgCardFrame()

                if let error = viewModel.errorMessage {
                    MtgErrorBanner(message: error)
                }

                Button {
                    Task {
                        if let destination = await viewModel.joinGame() {
                            navigationPath.append(destination)
                        }
                    }
                } label: {
                    if viewModel.isJoining {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.mtgBackground)
                            Text("Joining...")
                        }
                    } else {
                        Text("Join Game")
                    }
                }
                .buttonStyle(MtgPrimaryButtonStyle(isDisabled: viewModel.gameCode.count < 4 || viewModel.isJoining))
                .disabled(viewModel.gameCode.count < 4 || viewModel.isJoining)
                .accessibilityLabel(viewModel.isJoining ? "Joining game" : "Join game")

                Spacer()
            }
            .padding()
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { AnalyticsService.trackScreen("JoinGame") }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        JoinGameView(navigationPath: .preview)
    }
    .environmentObject(AuthViewModel())
}
#endif
