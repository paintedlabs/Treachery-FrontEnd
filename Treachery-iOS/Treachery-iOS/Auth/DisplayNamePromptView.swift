//
//  DisplayNamePromptView.swift
//  Treachery-iOS
//

import SwiftUI

struct DisplayNamePromptView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var displayName: String = ""
    /// The save in flight, if any. Skip cancels it so a late result can't
    /// act on a screen the user has left.
    @State private var saveTask: Task<Void, Never>?
    @State private var validationError: String?

    let onContinue: () -> Void

    private var isSaving: Bool { saveTask != nil }

    var body: some View {
        // Scrolls when the prompt is taller than the screen, as at the
        // largest text sizes with a failure shown, so Continue and Skip stay
        // reachable.
        FullHeightScrollView {
            prompt
        }
        .mtgRadialBackground()
        .onAppear {
            prefillName()
        }
    }

    private var prompt: some View {
        VStack(spacing: 16) {
            // Offline, a save waits for the connection; this says why.
            ConnectionBanner()

            Spacer()

            Text("Choose Your Name")
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundColor(.mtgGoldBright)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("This is how other players will see you")
                .font(.system(.subheadline, design: .serif))
                .italic()
                .foregroundColor(.mtgTextSecondary)
                .multilineTextAlignment(.center)

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
                FailureMessage(message: error)
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

            // Never disabled: offline, a save never finishes, and this is the
            // only way forward. A save already sent still lands once the
            // device is back online.
            Button {
                skip()
            } label: {
                Text("Skip")
                    .foregroundColor(.mtgGold)
                    .font(.system(.body, design: .serif))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }

            Spacer()
        }
        .padding(.horizontal)
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
            FailureMessage.announce(validationError)
            return
        }
        validationError = nil
        saveTask = Task {
            do {
                try await authViewModel.updateDisplayName(trimmed)
                guard !Task.isCancelled else { return }
                saveTask = nil
                onContinue()
            } catch {
                guard !Task.isCancelled else { return }
                // Stay on the prompt so the user can try again or skip.
                saveTask = nil
                let message = String(
                    localized: "Your name wasn't saved. \(UserFacingError(error).message)",
                    comment: "Shown on the name prompt when saving the chosen display name failed. The argument says why."
                )
                validationError = message
                FailureMessage.announce(message)
            }
        }
    }

    /// Moves on without waiting for a save in flight. Firestore keeps that
    /// write queued, so the name is still saved once the device is online.
    private func skip() {
        saveTask?.cancel()
        saveTask = nil
        onContinue()
    }
}
