//
//  LoginView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var isShowingSignUp = false
    @State private var isSigningIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()

            Text("Treachery")
                .font(.system(.largeTitle, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgGoldBright)
                .accessibilityAddTraits(.isHeader)

            Text("Enter the battlefield")
                .font(.subheadline)
                .foregroundStyle(Color.mtgTextSecondary)

            OrnateDivider()
                .padding(.vertical, 4)

            MtgTextField(placeholder: "Email", text: $email, keyboardType: .emailAddress)
                .textContentType(.emailAddress)
                .accessibilityLabel("Email address")

            MtgTextField(placeholder: "Password", text: $password, isSecure: true)
                .textContentType(.password)
                .accessibilityLabel("Password")
                .onSubmit {
                    guard !email.isEmpty && !password.isEmpty else { return }
                    signIn()
                }

            if let error = authViewModel.errorMessage {
                MtgErrorBanner(message: error)
            }

            Button {
                signIn()
            } label: {
                if isSigningIn {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.mtgBackground)
                        Text("Signing In...")
                    }
                } else {
                    Text("Sign In")
                }
            }
            .buttonStyle(MtgPrimaryButtonStyle(isDisabled: email.isEmpty || password.isEmpty || isSigningIn))
            .disabled(email.isEmpty || password.isEmpty || isSigningIn)
            .accessibilityLabel(isSigningIn ? "Signing in" : "Sign in")

            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.mtgDivider)
                    .frame(height: 1)
                Text("or")
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
                Rectangle()
                    .fill(Color.mtgDivider)
                    .frame(height: 1)
            }
            .padding(.vertical, 4)
            .accessibilityHidden(true)

            NavigationLink("Sign in with Phone") {
                PhoneAuthView()
            }
            .buttonStyle(MtgSecondaryButtonStyle())
            .accessibilityLabel("Sign in with phone number")

            Spacer()

            HStack {
                Button("Create Account") {
                    isShowingSignUp = true
                }
                .foregroundStyle(Color.mtgGold)
                .accessibilityLabel("Create a new account")

                Spacer()

                Button("Forgot Password?") {
                    guard !email.isEmpty else { return }
                    Task { await authViewModel.resetPassword(email: email) }
                }
                .font(.footnote)
                .foregroundStyle(Color.mtgTextSecondary)
                .disabled(email.isEmpty)
                .accessibilityLabel("Reset password")
                .accessibilityHint(email.isEmpty ? "Enter your email first" : "Sends a password reset email")
            }
        }
        .padding()
        .mtgBackground()
        .navigationDestination(isPresented: $isShowingSignUp) {
            SignUpView()
        }
    }

    private func signIn() {
        isSigningIn = true
        Task {
            await authViewModel.signIn(email: email, password: password)
            isSigningIn = false
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LoginView()
    }
    .environmentObject(AuthViewModel())
}
#endif
