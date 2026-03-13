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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()

            Text("Treachery")
                .font(.largeTitle)
                .fontWeight(.bold)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.emailAddress)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .onSubmit {
                    Task { await authViewModel.signIn(email: email, password: password) }
                }

            if let error = authViewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button("Sign In") {
                Task { await authViewModel.signIn(email: email, password: password) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty)

            Spacer()

            HStack {
                Button("Create Account") {
                    isShowingSignUp = true
                }

                Spacer()

                Button("Forgot Password?") {
                    Task { await authViewModel.resetPassword(email: email) }
                }
                .font(.footnote)
            }
        }
        .padding()
        .navigationDestination(isPresented: $isShowingSignUp) {
            SignUpView()
        }
    }
}
