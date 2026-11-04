//
//  LoginView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var isGuestLoading = false
    @State private var formVisible = false

    private var busy: Bool { isLoading || isGuestLoading }

    var body: some View {
        // Scrolls at the largest text sizes, where the form is taller than
        // the screen and Play as Guest would otherwise be cut off.
        FullHeightScrollView {
            form
        }
        .mtgRadialBackground()
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                formVisible = true
            }
        }
    }

    private var form: some View {
        VStack(alignment: .center, spacing: 18) {
            Spacer()

            // Title with glow
            VStack(spacing: 8) {
                Text("Treachery")
                    .font(.system(size: 42, weight: .bold, design: .serif))
                    .mtgGoldShimmer()
                    .shadow(color: Color.mtgGold.opacity(0.4), radius: 16, x: 0, y: 0)
                    .shadow(color: Color.mtgGold.opacity(0.2), radius: 32, x: 0, y: 0)
                    .accessibilityAddTraits(.isHeader)

                Text("A Game of Hidden Allegiance")
                    .font(.subheadline)
                    .foregroundStyle(Color.mtgTextSecondary)

                OrnateDivider()
                    .padding(.vertical, 4)
            }

            Spacer()
                .frame(height: 8)

            // Form content with fade-in animation
            Group {
                if let error = authViewModel.errorMessage {
                    FailureMessage(message: error)
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

                // Links row: stacked at the accessibility text sizes, where
                // side by side would break words in the middle.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        createAccountLink
                        forgotPasswordLink
                    }
                } else {
                    HStack {
                        createAccountLink
                        Spacer()
                        forgotPasswordLink
                    }
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
            }
            .opacity(formVisible ? 1 : 0)
            // With Reduce Motion the form only fades in; it doesn't slide up.
            .offset(y: formVisible || reduceMotion ? 0 : 12)

            Spacer()

            Link(destination: URL(string: "https://mtgtreachery.net")!) {
                Text("Learn the rules at MTGTreachery.net")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .font(.system(.caption, design: .serif))
            .italic()
            .foregroundStyle(Color.mtgTextSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
    }

    private var createAccountLink: some View {
        NavigationLink {
            SignUpView()
        } label: {
            Text("Create Account")
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .font(.subheadline)
        .foregroundStyle(Color.mtgGold)
    }

    private var forgotPasswordLink: some View {
        NavigationLink {
            ForgotPasswordView()
        } label: {
            Text("Forgot Password?")
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .font(.subheadline)
        .foregroundStyle(Color.mtgGold)
    }

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        Task {
            await authViewModel.signIn(email: email, password: password)
            isLoading = false
            // The failure appears above the form, away from Sign In.
            FailureMessage.announce(authViewModel.errorMessage)
        }
    }

    private func playAsGuest() {
        isGuestLoading = true
        Task {
            await authViewModel.signInAsGuest()
            isGuestLoading = false
            FailureMessage.announce(authViewModel.errorMessage)
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
