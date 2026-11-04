//
//  SignUpView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var localError: String?

    var body: some View {
        // Scrolls when the form is taller than the screen, as at the
        // largest text sizes.
        FullHeightScrollView {
            form
        }
        .mtgBackground()
        .navigationBarBackButtonHidden(isLoading)
    }

    private var form: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()

            Text("Create Account")
                .font(.system(.title, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgGoldBright)
                .accessibilityAddTraits(.isHeader)

            Text("Join the game of hidden allegiance")
                .font(.system(.subheadline, design: .serif))
                .italic()
                .foregroundStyle(Color.mtgTextSecondary)

            if let error = localError ?? authViewModel.errorMessage {
                FailureMessage(message: error)
            }

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding()
                .background(Color.mtgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mtgDivider, lineWidth: 1)
                )
                .cornerRadius(8)
                .foregroundStyle(Color.mtgTextPrimary)
                .disabled(isLoading)

            SecureField("Password", text: $password)
                .textContentType(.newPassword)
                .padding()
                .background(Color.mtgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mtgDivider, lineWidth: 1)
                )
                .cornerRadius(8)
                .foregroundStyle(Color.mtgTextPrimary)
                .disabled(isLoading)

            SecureField("Confirm Password", text: $confirmPassword)
                .textContentType(.newPassword)
                .padding()
                .background(Color.mtgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mtgDivider, lineWidth: 1)
                )
                .cornerRadius(8)
                .foregroundStyle(Color.mtgTextPrimary)
                .disabled(isLoading)

            Button {
                signUp()
            } label: {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.mtgBackground)
                        Text("Creating Account...")
                    }
                } else {
                    Text("Create Account")
                }
            }
            .buttonStyle(MtgPrimaryButtonStyle(isDisabled: isLoading))
            .disabled(isLoading)

            Button {
                dismiss()
            } label: {
                Text("Already have an account? Sign In")
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .font(.subheadline)
            .foregroundStyle(Color.mtgGold)
            .disabled(isLoading)

            Spacer()
        }
        .padding()
    }

    private func signUp() {
        localError = nil
        authViewModel.errorMessage = nil

        guard !email.isEmpty, !password.isEmpty else { return }

        // Each failure appears above the form, away from Create Account.
        guard password == confirmPassword else {
            localError = "Passwords do not match."
            FailureMessage.announce(localError)
            return
        }
        guard password.count >= 6 else {
            localError = "Password must be at least 6 characters."
            FailureMessage.announce(localError)
            return
        }

        isLoading = true
        Task {
            await authViewModel.signUp(email: email, password: password)
            isLoading = false
            FailureMessage.announce(authViewModel.errorMessage)
        }
    }
}
