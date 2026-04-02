#if DEBUG
//
//  AbilityTestingView.swift
//  Treachery-iOS
//
//  Dev-only tool for testing traitor ability UIs without a live game.
//

import SwiftUI

struct AbilityTestingView: View {
    @State private var selectedAbility: ExecutableAbility = .wearerOfMasks
    @State private var viewModel: GameBoardViewModel?
    @State private var showAbilitySheet = false
    @State private var stateLog: [String] = []

    private let cardDatabase = CardDatabase.shared

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    abilityPicker
                    scenarioDescription

                    if let vm = viewModel {
                        playerStateSection(vm)
                        triggerButton(vm)
                    } else {
                        setupButton
                    }

                    if !stateLog.isEmpty {
                        logSection
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Ability Testing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showAbilitySheet) {
            if let vm = viewModel {
                switch selectedAbility {
                case .metamorph:
                    MetamorphAbilitySheet(
                        viewModel: vm,
                        eliminatedPlayers: vm.players.filter { $0.isEliminated && $0.role != .leader }
                    )
                case .puppetMaster:
                    PuppetMasterAbilitySheet(
                        viewModel: vm,
                        players: vm.players.filter { !$0.isEliminated && $0.userId != "dev_user" }
                    )
                case .wearerOfMasks:
                    WearerOfMasksAbilitySheet(viewModel: vm)
                }
            }
        }
        .onChange(of: showAbilitySheet) { _, isShowing in
            if !isShowing, let vm = viewModel {
                logStateChange(vm)
            }
        }
        .onAppear { setupScenario() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.mtgGold)
            Text("Traitor Ability Tester")
                .font(.system(.title2, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgTextPrimary)
            Text("Test ability UIs with mock game state")
                .font(.caption)
                .foregroundStyle(Color.mtgTextSecondary)
        }
    }

    private var abilityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Ability")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgGold)

            Picker("Ability", selection: $selectedAbility) {
                ForEach(ExecutableAbility.allCases, id: \.self) { ability in
                    Text(ability.displayName).tag(ability)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedAbility) { _, _ in
                setupScenario()
            }
        }
        .padding()
        .background(Color.mtgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.mtgDivider, lineWidth: 1)
        )
    }

    private var scenarioDescription: some View {
        let card = cardDatabase.card(withId: selectedAbility.rawValue)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Card Ability")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgGold)

            if let card {
                Text(card.abilityText)
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.mtgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.mtgDivider, lineWidth: 1)
        )
    }

    private func playerStateSection(_ vm: GameBoardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Game State")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgGold)

            ForEach(vm.players) { player in
                let card = vm.identityCard(for: player)
                HStack(spacing: 8) {
                    Circle()
                        .fill(player.role?.color ?? .gray)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(player.displayName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.mtgTextPrimary)

                            if player.userId == "dev_user" {
                                MtgBadge(text: "YOU", foregroundColor: .mtgGold, backgroundColor: Color.mtgGold.opacity(0.15), fontWeight: .regular)
                            }

                            if player.isEliminated {
                                MtgBadge(text: "ELIMINATED", foregroundColor: .mtgError, backgroundColor: Color.mtgError.opacity(0.15), fontWeight: .regular)
                            }

                            if player.isFaceDown {
                                MtgBadge(text: "FACE DOWN", foregroundColor: .mtgTraitor, backgroundColor: Color.mtgTraitor.opacity(0.15), fontWeight: .regular)
                            }
                        }

                        Text("\(player.role?.displayName ?? "?") — \(card?.name ?? player.identityCardId ?? "none")")
                            .font(.caption2)
                            .foregroundStyle(Color.mtgTextSecondary)
                    }

                    Spacer()

                    Text("\(player.lifeTotal) HP")
                        .font(.caption)
                        .foregroundStyle(Color.mtgTextSecondary)
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color.mtgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.mtgDivider, lineWidth: 1)
        )
    }

    private func triggerButton(_ vm: GameBoardViewModel) -> some View {
        VStack(spacing: 12) {
            Button {
                showAbilitySheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("Trigger \(selectedAbility.displayName)")
                }
                .fontWeight(.semibold)
            }
            .buttonStyle(MtgPrimaryButtonStyle())

            Button {
                setupScenario()
                stateLog.removeAll()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Scenario")
                }
                .fontWeight(.medium)
            }
            .buttonStyle(MtgSecondaryButtonStyle())
        }
    }

    private var setupButton: some View {
        Button {
            setupScenario()
        } label: {
            Text("Setup Scenario")
                .fontWeight(.semibold)
        }
        .buttonStyle(MtgPrimaryButtonStyle())
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("State Changes")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.mtgGold)

                Spacer()

                Button("Clear") { stateLog.removeAll() }
                    .font(.caption2)
                    .foregroundStyle(Color.mtgTextSecondary)
            }

            ForEach(Array(stateLog.enumerated()), id: \.offset) { _, entry in
                Text(entry)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.mtgTextSecondary)
            }
        }
        .padding()
        .background(Color.mtgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.mtgDivider, lineWidth: 1)
        )
    }

    // MARK: - Scenario Setup

    private func setupScenario() {
        let allCards = cardDatabase.allCards

        // Pick real cards for each role
        let leaderCard = allCards.first { $0.role == .leader }
        let guardianCard = allCards.first { $0.role == .guardian }
        let assassinCard1 = allCards.first { $0.role == .assassin }
        let assassinCard2 = allCards.filter { $0.role == .assassin }.dropFirst().first

        let players: [Player] = [
            Player(id: "p1", orderId: 0, userId: "dev_leader", displayName: "Aragorn",
                   role: .leader, identityCardId: leaderCard?.id,
                   lifeTotal: 45, isEliminated: false, isUnveiled: false, joinedAt: Date()),
            Player(id: "p2", orderId: 1, userId: "dev_guardian", displayName: "Gandalf",
                   role: .guardian, identityCardId: guardianCard?.id,
                   lifeTotal: 40, isEliminated: false, isUnveiled: false, joinedAt: Date()),
            Player(id: "p3", orderId: 2, userId: "dev_assassin1", displayName: "Sauron",
                   role: .assassin, identityCardId: assassinCard1?.id,
                   lifeTotal: 35, isEliminated: false, isUnveiled: true, joinedAt: Date()),
            Player(id: "p4", orderId: 3, userId: "dev_user", displayName: "You (Traitor)",
                   role: .traitor, identityCardId: selectedAbility.rawValue,
                   lifeTotal: 40, isEliminated: false, isUnveiled: true, joinedAt: Date()),
            Player(id: "p5", orderId: 4, userId: "dev_assassin2", displayName: "Saruman",
                   role: .assassin, identityCardId: assassinCard2?.id,
                   lifeTotal: 0, isEliminated: true, isUnveiled: true, joinedAt: Date()),
        ]

        viewModel = GameBoardViewModel(
            gameId: "dev_test",
            previewPlayers: players,
            previewGame: .sampleInProgress,
            currentUserId: "dev_user"
        )

        stateLog.removeAll()
    }

    private func logStateChange(_ vm: GameBoardViewModel) {
        for player in vm.players {
            let card = vm.identityCard(for: player)
            var flags: [String] = []
            if player.isFaceDown { flags.append("face-down") }
            if player.originalIdentityCardId != nil { flags.append("swapped") }
            let flagStr = flags.isEmpty ? "" : " [\(flags.joined(separator: ", "))]"
            stateLog.append("\(player.displayName): \(card?.name ?? "?") (\(player.role?.displayName ?? "?"))\(flagStr)")
        }
        stateLog.append("---")
    }
}

#Preview("Ability Testing") {
    NavigationStack {
        AbilityTestingView()
    }
}
#endif
