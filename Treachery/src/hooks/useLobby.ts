import { useState, useEffect, useCallback, useRef } from 'react';
import { httpsCallable } from 'firebase/functions';
import { Game, Player } from '@/models/types';
import * as firestoreService from '@/services/firestore';
import { functions } from '@/config/firebase';
import { MINIMUM_PLAYER_COUNT } from '@/constants/roles';

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
      const startGameFn = httpsCallable(functions, 'startGame');
      await startGameFn({ gameId });
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to start game.');
    }
    setIsStartingGame(false);
  }, [isHost, game, gameId]);

  const leaveGame = useCallback(
    async (_userId: string) => {
      setErrorMessage(null);
      try {
        const leaveGameFn = httpsCallable(functions, 'leaveGame');
        await leaveGameFn({ gameId });
      } catch (error: any) {
        setErrorMessage(error.message || 'Failed to leave game.');
      }
    },
    [gameId]
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
