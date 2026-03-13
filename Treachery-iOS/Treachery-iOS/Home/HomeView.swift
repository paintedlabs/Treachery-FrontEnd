//
//  HomeView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text("Treachery")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                NavigationLink("Create Game") {
                    Text("Create Game — Coming Soon")
                }
                .buttonStyle(.borderedProminent)

                NavigationLink("Join Game") {
                    Text("Join Game — Coming Soon")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                }
                .padding(.bottom)
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}
