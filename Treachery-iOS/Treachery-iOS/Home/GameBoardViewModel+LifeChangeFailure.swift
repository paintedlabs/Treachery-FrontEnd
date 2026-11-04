//
//  GameBoardViewModel+LifeChangeFailure.swift
//  Treachery-iOS
//

import Foundation

extension GameBoardViewModel {

    /// A life change whose call failed, and what the board says about it.
    struct LifeChangeFailure: Equatable {
        /// What the board knows about the change.
        enum Kind: Equatable {
            /// No snapshot had shown the change when its call failed, so the
            /// board went back to the server's total. Most likely the change
            /// never reached the server, but a reply lost on its way back
            /// looks the same; see `revised(by:)`.
            case notApplied(baseline: Int, amount: Int)
            /// The board may show the change already, so making it again
            /// could apply it twice.
            case unconfirmed
            /// The server turned the change down, for this reason, so it
            /// certainly wasn't applied.
            case refused(reason: String)
        }

        /// A failure for VoiceOver to read out.
        struct Announcement: Equatable {
            let message: String
            /// Whether it may cut in on what VoiceOver is saying. Only the
            /// first of a burst may; the rest wait their turn, so one
            /// failure's message doesn't cut off another's.
            let interrupts: Bool
        }

        let playerId: String
        let playerName: String
        let kind: Kind

        /// What the board says about this failure alone, naming the player.
        var message: String {
            Self.sentence(for: wording, names: [playerName])
        }

        /// One banner for every failure the board still explains, naming
        /// everyone affected: a sentence for each thing to say, in the order
        /// the failures happened. Nil when there are none.
        static func bannerMessage(for failures: [Self]) -> String? {
            guard !failures.isEmpty else { return nil }
            var groups: [(wording: Wording, names: [String])] = []
            for failure in failures {
                if let index = groups.firstIndex(where: { $0.wording == failure.wording }) {
                    groups[index].names.append(failure.playerName)
                } else {
                    groups.append((failure.wording, [failure.playerName]))
                }
            }
            return groups.map { sentence(for: $0.wording, names: $0.names) }.joined(separator: " ")
        }

        /// What VoiceOver reads out when the failures go from `old` to `new`:
        /// each new or revised failure by itself, so a burst doesn't repeat
        /// the whole banner, and nothing for a failure that has gone.
        static func announcements(from old: [Self], to new: [Self]) -> [Announcement] {
            new.filter { !old.contains($0) }.enumerated().map { index, failure in
                Announcement(message: failure.message, interrupts: old.isEmpty && index == 0)
            }
        }

        /// This failure once a later snapshot shows the player's total. A
        /// change that wasn't applied as far as the board knew may have
        /// landed after all. A total that moved off the baseline by exactly
        /// the change means it did, and there's nothing left to explain
        /// (nil). Any other move can't be told apart from someone else's
        /// change, so the board can't confirm it, and "try again" could
        /// apply it twice.
        func revised(by player: Player) -> Self? {
            guard case .notApplied(let baseline, let amount) = kind,
                  player.lifeTotal != baseline else { return self }
            // The server stops at 0, as the board does.
            if player.lifeTotal == max(0, baseline + amount) { return nil }
            return Self(playerId: playerId, playerName: playerName, kind: .unconfirmed)
        }

        /// What the board says once `later`, a failure for the same player,
        /// follows this one. Two changes that never showed, sent from the
        /// same total, failed as one change of their sum, so a snapshot can
        /// still tell whether they landed. Otherwise the later one says what
        /// happened, unless either couldn't be confirmed: then the board
        /// still can't vouch for that player's total.
        func followed(by later: Self) -> Self {
            switch (kind, later.kind) {
            case let (.notApplied(baseline, amount), .notApplied(laterBaseline, laterAmount)) where baseline == laterBaseline:
                let sum = Kind.notApplied(baseline: baseline, amount: amount + laterAmount)
                return Self(playerId: playerId, playerName: later.playerName, kind: sum)
            case (.unconfirmed, _), (_, .unconfirmed), (.notApplied, .notApplied):
                return Self(playerId: playerId, playerName: later.playerName, kind: .unconfirmed)
            case (.notApplied, .refused), (.refused, _):
                return later
            }
        }

        // MARK: - Wording

        /// What the board says, setting aside who it's about.
        private enum Wording: Equatable {
            case tryAgain
            case checkTheTotal
            case refused(reason: String)
        }

        private var wording: Wording {
            switch kind {
            case .notApplied: return .tryAgain
            case .unconfirmed: return .checkTheTotal
            case .refused(let reason): return .refused(reason: reason)
            }
        }

        private static func sentence(for wording: Wording, names: [String]) -> String {
            // The app's text is English, so the list is too.
            let list = names.formatted(.list(type: .and).locale(Locale(identifier: "en")))
            let isOne = names.count == 1
            switch wording {
            case .tryAgain:
                return isOne
                    ? "Couldn't update \(list)'s life. Check your connection and try again."
                    : "Couldn't update life for \(list). Check your connection and try again."
            case .checkTheTotal:
                return isOne
                    ? "Couldn't confirm \(list)'s life change. Check the total before changing it again."
                    : "Couldn't confirm the life changes for \(list). Check their totals before changing them again."
            case .refused(let reason):
                return isOne
                    ? "Couldn't update \(list)'s life. \(reason)"
                    : "Couldn't update life for \(list). \(reason)"
            }
        }
    }

    /// `lifeChangeFailures` once a players snapshot shows `players`. A
    /// player shown eliminated loses theirs: the server refuses changes to
    /// them, and no tap could clear the message. Anyone else's is revised
    /// by where their total went; see `LifeChangeFailure.revised(by:)`.
    /// Once the game is over they stay as they are: Game Over covers the
    /// board, and a revision would only be read out over the results.
    func revisedLifeChangeFailures(by players: [Player]) -> [LifeChangeFailure] {
        guard !isGameFinished else { return lifeChangeFailures }
        return lifeChangeFailures.compactMap { failure in
            guard let player = players.first(where: { $0.id == failure.playerId }) else { return failure }
            return player.isEliminated ? nil : failure.revised(by: player)
        }
    }
}
