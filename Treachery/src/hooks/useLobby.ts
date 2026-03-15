import { useState, useEffect, useCallback, useRef } from 'react';
import { Timestamp } from 'firebase/firestore';
import { Game, Player, Role } from '@/models/types';
import * as firestoreService from '@/services/firestore';
import { getCardsForRole } from '@/services/cardDatabase';
import { getRoleDistribution, MINIMUM_PLAYER_COUNT } from '@/constants/roles';

interface UseLobbyReturn {
  game: Game | null;
  players: Player[];
  errorMessage: string | null;
  isStartingGame: boolean;
  isGameDisbanded: boolean;
  isGameStarted: boolean;
  canStartGame: boolean;
  startGame: () => Promise<void>;
  leaveGame: (userId: string) => Promise<void>;
}

export function useLobby(gameId: string, isHost: boolean): UseLobbyReturn {
  const [game, setGame] = useState<Game | null>(null);
  const [players, setPlayers] = useState<Player[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isStartingGame, setIsStartingGame] = useState(false);
  const [isGameDisbanded, setIsGameDisbanded] = useState(false);
  const hasReceivedFirstSnapshot = useRef(false);

  useEffect(() => {
    const unsubGame = firestoreService.listenToGame(gameId, (g) => {
      if (g === null && hasReceivedFirstSnapshot.current) {
        setIsGameDisbanded(true);
      }
      setGame(g);
      hasReceivedFirstSnapshot.current = true;
    });

    const unsubPlayers = firestoreService.listenToPlayers(gameId, (p) => {
      setPlayers(p);
    });

    return () => {
      unsubGame();
      unsubPlayers();
    };
  }, [gameId]);

  const isGameStarted = game?.state === 'in_progress';

  const canStartGame =
    isHost &&
    players.length >= MINIMUM_PLAYER_COUNT &&
    players.length <= (game?.max_players ?? 0);

  const startGame = useCallback(async () => {
    if (!isHost || !game) return;
    setErrorMessage(null);
    setIsStartingGame(true);

    try {
      const dist = getRoleDistribution(players.length);

      // Build shuffled role array
      const roles: Role[] = [];
      for (let i = 0; i < dist.leaders; i++) roles.push('leader');
      for (let i = 0; i < dist.guardians; i++) roles.push('guardian');
      for (let i = 0; i < dist.assassins; i++) roles.push('assassin');
      for (let i = 0; i < dist.traitors; i++) roles.push('traitor');

      // Shuffle
      for (let i = roles.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [roles[i], roles[j]] = [roles[j], roles[i]];
      }

      // Assign roles and cards
      const usedCardIds = new Set<string>();

      for (let i = 0; i < players.length; i++) {
        const role = roles[i];
        const availableCards = getCardsForRole(role).filter(
          (c) => !usedCardIds.has(c.id)
        );

        if (availableCards.length === 0) {
          throw new Error('Could not assign identity cards. Please try again.');
        }

        const card = availableCards[Math.floor(Math.random() * availableCards.length)];
        usedCardIds.add(card.id);

        const updatedPlayer: Player = {
          ...players[i],
          role,
          identity_card_id: card.id,
          life_total: game.starting_life + (card.life_modifier ?? 0),
        };

        await firestoreService.updatePlayer(updatedPlayer, gameId);
      }

      // Transition game state
      const updatedGame: Game = { ...game, state: 'in_progress' };
      await firestoreService.updateGame(updatedGame);
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to start game.');
    }
    setIsStartingGame(false);
  }, [isHost, game, players, gameId]);

  const leaveGame = useCallback(
    async (userId: string) => {
      setErrorMessage(null);
      try {
        const player = players.find((p) => p.user_id === userId);
        if (!player) return;
        await firestoreService.removePlayer(player.id, gameId);

        if (isHost) {
          await firestoreService.deleteGame(gameId);
        }
      } catch (error: any) {
        setErrorMessage(error.message || 'Failed to leave game.');
      }
    },
    [players, gameId, isHost]
  );

  return {
    game,
    players,
    errorMessage,
    isStartingGame,
    isGameDisbanded,
    isGameStarted,
    canStartGame,
    startGame,
    leaveGame,
  };
}
