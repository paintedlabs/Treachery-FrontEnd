//
//  APIViewModel.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/11/24.
//

import SwiftUI


enum APIViewModelState {
  case protected
  case notProtected
}

class APIViewModel: ObservableObject {

  @Published var state: APIViewModelState = .notProtected
  

  func helloWorld() {
    URLSession.shared.dataTask(with: URL(string: "http://192.168.104:8080/api/public/helloworld")!) { data, response, error in
      if let data = data {
        if let string = String(data: data, encoding: .utf8) {
          print(string)
        }
      }
    }.resume()
  }

}
