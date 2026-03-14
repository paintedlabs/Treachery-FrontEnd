//
//  PhoneAuthView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/13/26.
//

import SwiftUI

struct PhoneAuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var isVerifying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if authViewModel.isAwaitingVerification {
                // Step 2: Enter verification code
                Text("Enter Verification Code")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)

                Text("A 6-digit code was sent to \(phoneNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("000000", text: $verificationCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title2.monospaced())
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Verification code")
                    .accessibilityHint("Enter the 6-digit code sent to your phone")
                    .onChange(of: verificationCode) { _, newValue in
                        verificationCode = String(newValue.prefix(6))
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
                    verify()
                } label: {
                    if isVerifying {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("Verifying...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Verify")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(verificationCode.count < 6 || isVerifying)
                .accessibilityLabel(isVerifying ? "Verifying code" : "Verify code")

                Button("Use a different number") {
                    verificationCode = ""
                    authViewModel.cancelPhoneVerification()
                }
                .font(.footnote)
                .accessibilityLabel("Go back and use a different phone number")
            } else {
                // Step 1: Enter phone number
                Text("Phone Sign In")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)

                Text("Enter your phone number with country code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("+1 555-123-4567", text: $phoneNumber)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .accessibilityLabel("Phone number")
                    .accessibilityHint("Include country code, e.g. plus 1 for US")

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
                    Task { await authViewModel.sendVerificationCode(phoneNumber: phoneNumber) }
                } label: {
                    if authViewModel.isSendingCode {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("Sending...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Send Verification Code")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(phoneNumber.isEmpty || authViewModel.isSendingCode)
                .accessibilityLabel(authViewModel.isSendingCode ? "Sending verification code" : "Send verification code")
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Phone Sign In")
        .onDisappear {
            authViewModel.cancelPhoneVerification()
        }
    }

    private func verify() {
        isVerifying = true
        Task {
            await authViewModel.verifyCode(verificationCode)
            isVerifying = false
        }
    }
}

#if DEBUG
#Preview("Enter Phone Number") {
    NavigationStack {
        PhoneAuthView()
    }
    .environmentObject(AuthViewModel())
}
#endif
