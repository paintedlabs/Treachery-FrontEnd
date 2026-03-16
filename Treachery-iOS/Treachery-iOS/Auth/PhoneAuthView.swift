//
//  PhoneAuthView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/16/26.
//

import SwiftUI

struct PhoneAuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var verificationID: String?
    @State private var isLoading = false

    private var isCodeStep: Bool { verificationID != nil }

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()

            Text("Phone Sign In")
                .font(.system(.title, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgGoldBright)
                .accessibilityAddTraits(.isHeader)

            Text(isCodeStep
                 ? "Enter the 6-digit code sent to your phone"
                 : "Enter your phone number to receive a code")
                .font(.system(.subheadline, design: .serif))
                .italic()
                .foregroundStyle(Color.mtgTextSecondary)
                .multilineTextAlignment(.center)

            if let error = authViewModel.errorMessage {
                MtgErrorBanner(message: error)
            }

            if !isCodeStep {
                // Phone number entry
                TextField("Phone number (e.g. +15551234567)", text: $phoneNumber)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
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
                    sendCode()
                } label: {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.mtgBackground)
                            Text("Sending...")
                        }
                    } else {
                        Text("Send Code")
                    }
                }
                .buttonStyle(MtgPrimaryButtonStyle(isDisabled: isLoading))
                .disabled(isLoading)
            } else {
                // Verification code entry
                TextField("6-digit code", text: $verificationCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
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
                    verifyCode()
                } label: {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.mtgBackground)
                            Text("Verifying...")
                        }
                    } else {
                        Text("Verify Code")
                    }
                }
                .buttonStyle(MtgPrimaryButtonStyle(isDisabled: isLoading))
                .disabled(isLoading)

                Button("Use a different number") {
                    verificationID = nil
                    verificationCode = ""
                    authViewModel.errorMessage = nil
                }
                .font(.subheadline)
                .foregroundStyle(Color.mtgGold)
                .disabled(isLoading)
            }

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
    }

    private func sendCode() {
        let formatted = phoneNumber.trimmingCharacters(in: .whitespaces)
        let number = formatted.hasPrefix("+") ? formatted : "+1\(formatted)"
        guard number.count >= 10 else {
            authViewModel.errorMessage = "Please enter a valid phone number."
            return
        }

        isLoading = true
        Task {
            let id = await authViewModel.verifyPhoneNumber(number)
            verificationID = id
            isLoading = false
        }
    }

    private func verifyCode() {
        guard let id = verificationID, !verificationCode.isEmpty else { return }
        isLoading = true
        Task {
            await authViewModel.signInWithPhoneCode(verificationID: id, code: verificationCode)
            isLoading = false
        }
    }
}
