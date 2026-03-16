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
    @State private var isLoading = false
    @State private var isGuestLoading = false

    private var busy: Bool { isLoading || isGuestLoading }

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()

            Text("Treachery")
                .font(.system(.largeTitle, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgGoldBright)
                .accessibilityAddTraits(.isHeader)

            Text("A Game of Hidden Allegiance")
                .font(.subheadline)
                .foregroundStyle(Color.mtgTextSecondary)

            OrnateDivider()
                .padding(.vertical, 4)

            if let error = authViewModel.errorMessage {
                MtgErrorBanner(message: error)
            }

            // Email/Password fields
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
                .disabled(busy)

            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding()
                .background(Color.mtgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mtgDivider, lineWidth: 1)
                )
                .cornerRadius(8)
                .foregroundStyle(Color.mtgTextPrimary)
                .disabled(busy)

            // Sign In button
            Button {
                signIn()
            } label: {
                if isLoading {
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
            .buttonStyle(MtgPrimaryButtonStyle(isDisabled: busy))
            .disabled(busy)

            // Links row
            HStack {
                NavigationLink("Create Account") {
                    SignUpView()
                }
                .font(.subheadline)
                .foregroundStyle(Color.mtgGold)

                Spacer()

                NavigationLink("Forgot Password?") {
                    ForgotPasswordView()
                }
                .font(.subheadline)
                .foregroundStyle(Color.mtgGold)
            }

            // Phone sign in
            NavigationLink {
                PhoneAuthView()
            } label: {
                Text("Sign In with Phone")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.mtgTextPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.mtgDivider, lineWidth: 1)
                    )
            }
            .disabled(busy)

            // Divider
            HStack(spacing: 12) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color.mtgDivider)
                Text("or")
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color.mtgDivider)
            }

            // Guest button
            Button {
                playAsGuest()
            } label: {
                if isGuestLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.mtgGold)
                        Text("Joining...")
                    }
                } else {
                    Text("Play as Guest")
                }
            }
            .buttonStyle(MtgSecondaryButtonStyle())
            .disabled(busy)

            Spacer()

            Link("Learn the rules at MTGTreachery.net",
                 destination: URL(string: "https://mtgtreachery.net")!)
                .font(.system(.caption, design: .serif))
                .italic()
                .foregroundStyle(Color.mtgTextSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .mtgBackground()
    }

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        Task {
            await authViewModel.signIn(email: email, password: password)
            isLoading = false
        }
    }

    private func playAsGuest() {
        isGuestLoading = true
        Task {
            await authViewModel.signInAsGuest()
            isGuestLoading = false
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
