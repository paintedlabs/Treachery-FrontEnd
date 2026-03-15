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
                ZStack {
                    Color.mtgBackground.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("Treachery")
                            .font(.system(size: 36, weight: .bold, design: .serif))
                            .foregroundStyle(Color.mtgGoldBright)
                        ProgressView()
                            .tint(Color.mtgGold)
                    }
                }
            case .authenticated:
                HomeView()
            case .unauthenticated:
                NavigationStack {
                    LoginView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
#Preview {
    RootView()
        .environmentObject(AuthViewModel())
}
#endif
