//
//  SignUpView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var validationError: String?
    @State private var isCreating = false

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MtgSectionHeader(title: "Create Your Account")
                .padding(.top, 8)

            OrnateDivider()

            MtgTextField(placeholder: "Email", text: $email, keyboardType: .emailAddress)
                .textContentType(.emailAddress)
                .accessibilityLabel("Email address")

            MtgTextField(placeholder: "Password", text: $password, isSecure: true)
                .textContentType(.newPassword)
                .accessibilityLabel("Password")

            MtgTextField(placeholder: "Confirm Password", text: $confirmPassword, isSecure: true)
                .textContentType(.newPassword)
                .accessibilityLabel("Confirm password")

            // Password match indicator
            if !confirmPassword.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(passwordsMatch ? Color.mtgSuccess : Color.mtgError)
                        .font(.caption)
                    Text(passwordsMatch ? "Passwords match" : "Passwords do not match")
                        .foregroundStyle(passwordsMatch ? Color.mtgSuccess : Color.mtgError)
                        .font(.caption)
                }
                .accessibilityElement(children: .combine)
            }

            if let error = validationError ?? authViewModel.errorMessage {
                MtgErrorBanner(message: error)
            }

            Button {
                createAccount()
            } label: {
                if isCreating {
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
            .buttonStyle(MtgPrimaryButtonStyle(isDisabled: email.isEmpty || password.isEmpty || confirmPassword.isEmpty || isCreating))
            .disabled(email.isEmpty || password.isEmpty || confirmPassword.isEmpty || isCreating)
            .accessibilityLabel(isCreating ? "Creating account" : "Create account")

            // Password requirements hint
            if password.isEmpty {
                Text("Password must be at least 6 characters")
                    .font(.caption2)
                    .foregroundStyle(Color.mtgTextSecondary)
            }

            Spacer()
        }
        .padding()
        .mtgBackground()
        .navigationTitle("Sign Up")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func createAccount() {
        guard password == confirmPassword else {
            validationError = "Passwords do not match."
            return
        }
        guard password.count >= 6 else {
            validationError = "Password must be at least 6 characters."
            return
        }
        validationError = nil
        isCreating = true
        Task {
            await authViewModel.signUp(email: email, password: password)
            isCreating = false
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SignUpView()
    }
    .environmentObject(AuthViewModel())
}
#endif
