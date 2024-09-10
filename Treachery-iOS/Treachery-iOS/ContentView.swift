//
//  ContentView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/10/24.
//

import SwiftUI
import SwiftData


enum ContentViewModelState {
  case notAuthenticated
  case authenticated

  var isAuthenticated: Bool {
    switch self {
      case .authenticated: return true
      default: return false
    }
  }

  var bodyText: String {
    switch self {
      case .notAuthenticated: return "Not Authenticated"
      case .authenticated: return "Authenticated"
    }
  }

}

class ContentViewModel: ObservableObject {
  @Published var text = "Hello, World!"
}

struct ContentView: View {
  @ObservedObject var viewModel: ContentViewModel

    var body: some View {
      Text(viewModel.text)
        .padding()
    }
}

//MARK: - Preview
#Preview {
  ContentView(viewModel: ContentViewModel())
}
