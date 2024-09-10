//
//  ContentView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/10/24.
//

import SwiftUI

struct ContentView: View {
  @ObservedObject var viewModel: ContentViewModel

    var body: some View {

      VStack (alignment: .leading, spacing: 0) {
        Text("Email:")
        TextField("Email", text: $viewModel.email)
          .padding()
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)

        Text("Password")
        SecureField("Password", text: $viewModel.password)
          .padding()
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
          .onSubmit {
            viewModel.authenticate()
          }

        Text(viewModel.state.bodyText)
          .foregroundStyle(.red)
          .fontWeight(.bold)
          .padding()

        Button {
          viewModel.authenticate()
        } label: {
          Text("Login")
        }
      }
      .padding()
    }
}

//MARK: - Preview
#Preview {
  ContentView(viewModel: ContentViewModel(firebaseManager: FirebaseManager()))
}
