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
                .font(.largeTitle)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

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
                .disableAutocorrection(true)
                .textContentType(.password)
                .accessibilityLabel("Password")
                .onSubmit {
                    guard !email.isEmpty && !password.isEmpty else { return }
                    signIn()
                }

            if let error = authViewModel.errorMessage {
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
                signIn()
            } label: {
                if isSigningIn {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Signing In...")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty || isSigningIn)
            .accessibilityLabel(isSigningIn ? "Signing in" : "Sign in")

            HStack {
                VStack { Divider() }
                Text("or")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack { Divider() }
            }
            .padding(.vertical, 4)
            .accessibilityHidden(true)

            NavigationLink("Sign in with Phone") {
                PhoneAuthView()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Sign in with phone number")

            Spacer()

            HStack {
                Button("Create Account") {
                    isShowingSignUp = true
                }
                .accessibilityLabel("Create a new account")

                Spacer()

                Button("Forgot Password?") {
                    guard !email.isEmpty else { return }
                    Task { await authViewModel.resetPassword(email: email) }
                }
                .font(.footnote)
                .disabled(email.isEmpty)
                .accessibilityLabel("Reset password")
                .accessibilityHint(email.isEmpty ? "Enter your email first" : "Sends a password reset email")
            }
        }
        .padding()
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
