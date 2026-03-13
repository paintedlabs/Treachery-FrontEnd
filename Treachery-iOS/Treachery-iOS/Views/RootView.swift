//
//  RootView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .loading:
                ProgressView("Loading...")
            case .authenticated:
                HomeView()
            case .unauthenticated:
                NavigationStack {
                    LoginView()
                }
            }
        }
    }
}
