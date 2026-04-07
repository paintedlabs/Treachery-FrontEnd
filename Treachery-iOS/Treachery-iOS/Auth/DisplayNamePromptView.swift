//
//  DisplayNamePromptView.swift
//  Treachery-iOS
//

import SwiftUI

struct DisplayNamePromptView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var displayName: String = ""
    @State private var isSaving = false
    @State private var validationError: String?

    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Choose Your Name")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundColor(.mtgGoldBright)

            Text("This is how other players will see you")
                .font(.system(.subheadline, design: .serif))
                .italic()
                .foregroundColor(.mtgTextSecondary)

            OrnateDivider()
                .padding(.vertical, 8)

            TextField("Display Name", text: $displayName)
                .textFieldStyle(.plain)
                .padding(14)
                .background(Color.mtgSurface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mtgDivider, lineWidth: 1)
                )
                .foregroundColor(.mtgTextPrimary)
                .textContentType(.name)
                .autocapitalization(.words)
                .disabled(isSaving)
                .onChange(of: displayName) { _, newValue in
                    if newValue.count > 30 {
                        displayName = String(newValue.prefix(30))
                    }
                }

            if let error = validationError {
                MtgErrorBanner(message: error)
            }

            Button {
                handleContinue()
            } label: {
                if isSaving {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color(.systemBackground))
                        Text("Saving...")
                    }
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(MtgPrimaryButtonStyle())
            .disabled(isSaving)

            Button {
                onContinue()
            } label: {
                Text("Skip")
                    .foregroundColor(.mtgGold)
                    .font(.system(.body, design: .serif))
            }
            .disabled(isSaving)

            Spacer()
        }
        .padding(.horizontal)
        .mtgRadialBackground()
        .onAppear {
            prefillName()
        }
    }

    private func prefillName() {
        if case .authenticated(let user) = authViewModel.authState {
            if let email = user.email, !email.isEmpty {
                let prefix = email.components(separatedBy: "@").first ?? ""
                let capitalized = prefix.prefix(1).uppercased() + prefix.dropFirst()
                displayName = capitalized
            } else if user.isAnonymous {
                displayName = "Guest"
            } else {
                displayName = "Player"
            }
        }
    }

    private func handleContinue() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationError = "Please enter a display name."
            return
        }
        validationError = nil
        isSaving = true
        Task {
            await authViewModel.updateDisplayName(trimmed)
            isSaving = false
            onContinue()
        }
    }
}
