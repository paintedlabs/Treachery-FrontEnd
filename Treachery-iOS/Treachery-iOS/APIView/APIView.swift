//
//  APIView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 9/11/24.
//

import SwiftUI

struct APIView {

  @ObservedObject var viewModel: APIViewModel

  var body: some View {
    VStack (alignment: .leading, spacing: 0) {
      Button {
        viewModel.helloWorld()
      } label: {
        Text("Login")
      }
    }
  }

}
