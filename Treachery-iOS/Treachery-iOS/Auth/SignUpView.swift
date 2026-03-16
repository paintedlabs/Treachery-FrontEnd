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
                MtgErrorBanner(message: error)
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

            Button("Already have an account? Sign In") {
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(Color.mtgGold)
            .disabled(isLoading)

            Spacer()
        }
        .padding()
        .mtgBackground()
        .navigationBarBackButtonHidden(isLoading)
    }

    private func signUp() {
        localError = nil
        authViewModel.errorMessage = nil

        guard !email.isEmpty, !password.isEmpty else { return }

        guard password == confirmPassword else {
            localError = "Passwords do not match."
            return
        }
        guard password.count >= 6 else {
            localError = "Password must be at least 6 characters."
            return
        }

        isLoading = true
        Task {
            await authViewModel.signUp(email: email, password: password)
            isLoading = false
        }
    }
}
