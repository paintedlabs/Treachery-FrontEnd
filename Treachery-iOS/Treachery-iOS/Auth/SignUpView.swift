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
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .accessibilityLabel("Email address")

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .textContentType(.newPassword)
                .accessibilityLabel("Password")

            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .textContentType(.newPassword)
                .accessibilityLabel("Confirm password")

            // Password match indicator
            if !confirmPassword.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(passwordsMatch ? .green : .red)
                        .font(.caption)
                    Text(passwordsMatch ? "Passwords match" : "Passwords do not match")
                        .foregroundStyle(passwordsMatch ? .green : .red)
                        .font(.caption)
                }
                .accessibilityElement(children: .combine)
            }

            if let error = validationError ?? authViewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(error)")
            }

            Button {
                createAccount()
            } label: {
                if isCreating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Creating Account...")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Create Account")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty || confirmPassword.isEmpty || isCreating)
            .accessibilityLabel(isCreating ? "Creating account" : "Create account")

            // Password requirements hint
            if password.isEmpty {
                Text("Password must be at least 6 characters")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Sign Up")
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
