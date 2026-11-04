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
                FailureMessage(message: error)
            }

            if !isCodeStep {
                // Phone number entry. The format goes under the field, where
                // it wraps: as part of the placeholder it was cut off at the
                // larger text sizes, and gone once typing started. The name
                // goes above the field at the accessibility sizes.
                VStack(alignment: .leading, spacing: 6) {
                    LabeledField("Phone number") { placeholder in
                        TextField("Phone number", text: $phoneNumber, prompt: placeholder)
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
                    }

                    Text("Include your country code, like +15551234567.")
                        .font(.footnote)
                        .foregroundStyle(Color.mtgTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Grouped, so VoiceOver reads the number in parts.
                        .accessibilityLabel("Include your country code, like +1 555 123 4567.")
                }

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

                Button {
                    verificationID = nil
                    verificationCode = ""
                    authViewModel.errorMessage = nil
                } label: {
                    Text("Use a different number")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.subheadline)
                .foregroundStyle(Color.mtgGold)
                .disabled(isLoading)
            }

            Button {
                dismiss()
            } label: {
                Text("Back to Sign In")
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

    private func sendCode() {
        let formatted = phoneNumber.trimmingCharacters(in: .whitespaces)
        let number = formatted.hasPrefix("+") ? formatted : "+1\(formatted)"
        // Each failure appears above the form, away from the button.
        guard number.count >= 10 else {
            authViewModel.errorMessage = "Please enter a valid phone number."
            FailureMessage.announce(authViewModel.errorMessage)
            return
        }

        isLoading = true
        Task {
            let id = await authViewModel.verifyPhoneNumber(number)
            verificationID = id
            isLoading = false
            FailureMessage.announce(authViewModel.errorMessage)
        }
    }

    private func verifyCode() {
        guard let id = verificationID, !verificationCode.isEmpty else { return }
        isLoading = true
        Task {
            await authViewModel.signInWithPhoneCode(verificationID: id, code: verificationCode)
            isLoading = false
            FailureMessage.announce(authViewModel.errorMessage)
        }
    }
}
