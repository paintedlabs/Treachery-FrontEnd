import { useState, useEffect, useCallback, useRef } from 'react';
import { httpsCallable } from 'firebase/functions';
import { Game, Player } from '@/models/types';
import * as firestoreService from '@/services/firestore';
import { functions } from '@/config/firebase';
import { MINIMUM_PLAYER_COUNT } from '@/constants/roles';
import { trackEvent } from '@/services/analytics';

interface UseLobbyReturn {
  game: Game | null;
  players: Player[];
  errorMessage: string | null;
  isStartingGame: boolean;
  isGameDisbanded: boolean;
  isGameStarted: boolean;
  canStartGame: boolean;
  allPlayersReady: boolean;
  minPlayers: number;
  startGame: () => Promise<void>;
  leaveGame: (userId: string) => Promise<void>;
  updatePlayerColor: (color: string | null) => Promise<void>;
  updateCommanderName: (name: string | null) => Promise<void>;
  toggleReady: () => Promise<void>;
  updateGameSettings: (settings: { maxPlayers?: number; startingLife?: number; gameMode?: string }) => Promise<void>;
}

export function useLobby(
  gameId: string,
  isHost: boolean,
  currentUserId?: string | null,
): UseLobbyReturn {
  const [game, setGame] = useState<Game | null>(null);
  const [players, setPlayers] = useState<Player[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isStartingGame, setIsStartingGame] = useState(false);
  const [isGameDisbanded, setIsGameDisbanded] = useState(false);
  const hasReceivedFirstSnapshot = useRef(false);
  const unsubGameRef = useRef<(() => void) | null>(null);
  const unsubPlayersRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    unsubGameRef.current = firestoreService.listenToGame(gameId, (g) => {
      if (g === null && hasReceivedFirstSnapshot.current) {
        setIsGameDisbanded(true);
      }
      setGame(g);
      hasReceivedFirstSnapshot.current = true;
    });

    unsubPlayersRef.current = firestoreService.listenToPlayers(gameId, (p) => {
      setPlayers(p);
    });

    return () => {
      unsubGameRef.current?.();
      unsubPlayersRef.current?.();
    };
  }, [gameId]);

  const isGameStarted = game?.state === 'in_progress';

  const isTreacheryMode =
    game?.game_mode === 'treachery' || game?.game_mode === 'treachery_planechase';
  const minPlayers = isTreacheryMode ? MINIMUM_PLAYER_COUNT : 1;

  const allPlayersReady = players.length < 2 || players.every((p) => p.is_ready);
  const canStartGame = isHost && players.length >= minPlayers && allPlayersReady;

  const startGame = useCallback(async () => {
    if (!isHost || !game) return;
    setErrorMessage(null);
    setIsStartingGame(true);

    try {
      const startGameFn = httpsCallable(functions, 'startGame');
      await startGameFn({ gameId });
      trackEvent('start_game', { player_count: players.length, game_mode: game.game_mode ?? 'unknown' });
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to start game.');
    }
    setIsStartingGame(false);
  }, [isHost, game, gameId, players.length]);

  const leaveGame = useCallback(
    async (_userId: string) => {
      setErrorMessage(null);
      // Stop listeners before leaving to prevent race conditions
      // where snapshot updates re-render the view mid-navigation
      unsubGameRef.current?.();
      unsubPlayersRef.current?.();
      try {
        const leaveGameFn = httpsCallable(functions, 'leaveGame');
        await leaveGameFn({ gameId });
        trackEvent('leave_lobby');
      } catch (error: unknown) {
        setErrorMessage(error instanceof Error ? error.message : 'Failed to leave game.');
      }
    },
    [gameId],
  );

  const currentPlayer = players.find((p) => p.user_id === currentUserId) ?? null;

  const updatePlayerColor = useCallback(
    async (color: string | null) => {
      if (!currentPlayer) return;
      try {
        await firestoreService.updatePlayerColor(gameId, currentPlayer.id, color);
      } catch (error: unknown) {
        setErrorMessage(error instanceof Error ? error.message : 'Failed to update color.');
      }
    },
    [gameId, currentPlayer],
  );

  const updateCommanderName = useCallback(
    async (name: string | null) => {
      if (!currentPlayer) return;
      try {
        await firestoreService.updateCommanderName(gameId, currentPlayer.id, name);
      } catch (error: unknown) {
        setErrorMessage(
          error instanceof Error ? error.message : 'Failed to update commander name.',
        );
      }
    },
    [gameId, currentPlayer],
  );

  const toggleReady = useCallback(async () => {
    if (!currentPlayer) return;
    try {
      await firestoreService.updatePlayerReady(gameId, currentPlayer.id, !currentPlayer.is_ready);
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to update ready status.');
    }
  }, [gameId, currentPlayer]);

  const updateGameSettings = useCallback(
    async (settings: { maxPlayers?: number; startingLife?: number; gameMode?: string }) => {
      if (!isHost || !game) return;
      try {
        const fn = httpsCallable(functions, 'updateGameSettings');
        await fn({ gameId, ...settings });
      } catch (error: unknown) {
        setErrorMessage(error instanceof Error ? error.message : 'Failed to update settings.');
      }
    },
    [isHost, game, gameId],
  );

  return {
    game,
    players,
    errorMessage,
    isStartingGame,
    isGameDisbanded,
    isGameStarted,
    canStartGame,
    allPlayersReady,
    minPlayers,
    startGame,
    leaveGame,
    updatePlayerColor,
    updateCommanderName,
    toggleReady,
    updateGameSettings,
  };
}
