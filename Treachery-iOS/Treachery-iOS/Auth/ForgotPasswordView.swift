//
//  ForgotPasswordView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/16/26.
//

import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var isLoading = false
    @State private var didSend = false

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()

            Text("Reset Password")
                .font(.system(.title, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgGoldBright)
                .accessibilityAddTraits(.isHeader)

            Text("Enter your email and we'll send you a reset link.")
                .font(.system(.subheadline, design: .serif))
                .italic()
                .foregroundStyle(Color.mtgTextSecondary)
                .multilineTextAlignment(.center)

            if let error = authViewModel.errorMessage {
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

            Button {
                sendReset()
            } label: {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.mtgBackground)
                        Text("Sending...")
                    }
                } else {
                    Text("Send Reset Link")
                }
            }
            .buttonStyle(MtgPrimaryButtonStyle(isDisabled: isLoading))
            .disabled(isLoading)

            Button("Back to Sign In") {
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
        .alert("Email Sent", isPresented: $didSend) {
            Button("OK") { dismiss() }
        } message: {
            Text("Check your inbox for a password reset link.")
        }
    }

    private func sendReset() {
        guard !email.isEmpty else { return }
        isLoading = true
        Task {
            await authViewModel.resetPassword(email: email)
            isLoading = false
            if authViewModel.errorMessage == nil {
                didSend = true
            }
        }
    }
}
