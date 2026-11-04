import { useState, useEffect, useCallback, useRef } from 'react';
import { httpsCallable, FunctionsError } from 'firebase/functions';
import type { FunctionsErrorCode } from 'firebase/functions';
import { Game, Player, Rarity } from '@/models/types';
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
  isHost: boolean;
  canStartGame: boolean;
  minPlayers: number;
  startGame: () => Promise<void>;
  leaveGame: (userId: string) => Promise<void>;
  updatePlayerColor: (color: string | null) => Promise<void>;
  updateCommanderName: (name: string | null) => Promise<void>;
  updateGameSettings: (settings: {
    maxPlayers?: number;
    startingLife?: number;
    gameMode?: string;
    maxTraitorRarity?: Rarity;
  }) => Promise<void>;
}

// What a failed lobby action tells the player. Firebase's own text is not
// meant for players: a callable that can't reach the server fails with the
// bare word "internal", and a refused Firestore write (color, commander name)
// says "Missing or insufficient permissions."
function lobbyErrorMessage(error: unknown, failed: string): string {
  if (error instanceof FunctionsError) {
    switch (error.code as FunctionsErrorCode) {
      // The lobby callables write these refusals for players, such as
      // "Cannot set max players below the current lobby size." Only a
      // sentence the server wrote is shown: when a response carries no
      // message, the SDK falls back to the bare code or status
      // ("invalid-argument", "FAILED_PRECONDITION"), which isn't for players.
      case 'functions/failed-precondition':
      case 'functions/invalid-argument': {
        const message = error.message.trim();
        const isBareCode = /^[A-Za-z_-]+$/.test(message);
        return message && !isBareCode ? message : `${failed} Try again.`;
      }
      // Offline, timed out, or the server failed.
      case 'functions/internal':
      case 'functions/unavailable':
      case 'functions/deadline-exceeded':
        return `${failed} Check your connection and try again.`;
    }
  }
  return `${failed} Try again.`;
}

export function useLobby(
  gameId: string,
  _navIsHost: boolean,
  currentUserId?: string | null,
): UseLobbyReturn {
  const [game, setGame] = useState<Game | null>(null);
  const [players, setPlayers] = useState<Player[]>([]);
  // Every action clears this before it runs, so a repeated failure with the
  // same message still reads as a new error (the lobby scrolls to it).
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

  // Always derive host from live game data so host promotion works.
  const isHost = !!currentUserId && game?.host_id === currentUserId;

  const isTreacheryMode =
    game?.game_mode === 'treachery' || game?.game_mode === 'treachery_planechase';
  const minPlayers = isTreacheryMode ? MINIMUM_PLAYER_COUNT : 1;

  const canStartGame = isHost && players.length >= minPlayers;

  const startGame = useCallback(async () => {
    if (!game || !currentUserId || game.host_id !== currentUserId) return;
    setErrorMessage(null);
    setIsStartingGame(true);

    try {
      const startGameFn = httpsCallable(functions, 'startGame');
      await startGameFn({ gameId });
      trackEvent('start_game', {
        player_count: players.length,
        game_mode: game.game_mode ?? 'unknown',
      });
    } catch (error: unknown) {
      setErrorMessage(lobbyErrorMessage(error, "Couldn't start the game."));
    }
    setIsStartingGame(false);
  }, [game, currentUserId, gameId, players.length]);

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
        setErrorMessage(lobbyErrorMessage(error, "Couldn't leave the game."));
      }
    },
    [gameId],
  );

  const currentPlayer = players.find((p) => p.user_id === currentUserId) ?? null;

  const updatePlayerColor = useCallback(
    async (color: string | null) => {
      if (!currentPlayer) return;
      setErrorMessage(null);
      try {
        await firestoreService.updatePlayerColor(gameId, currentPlayer.id, color);
      } catch (error: unknown) {
        setErrorMessage(lobbyErrorMessage(error, "Couldn't update your color."));
      }
    },
    [gameId, currentPlayer],
  );

  const updateCommanderName = useCallback(
    async (name: string | null) => {
      if (!currentPlayer) return;
      setErrorMessage(null);
      try {
        await firestoreService.updateCommanderName(gameId, currentPlayer.id, name);
      } catch (error: unknown) {
        setErrorMessage(lobbyErrorMessage(error, "Couldn't update your commander name."));
      }
    },
    [gameId, currentPlayer],
  );

  const updateGameSettings = useCallback(
    async (settings: {
      maxPlayers?: number;
      startingLife?: number;
      gameMode?: string;
      maxTraitorRarity?: Rarity;
    }) => {
      if (!game || !currentUserId || game.host_id !== currentUserId) return;
      setErrorMessage(null);
      try {
        const fn = httpsCallable(functions, 'updateGameSettings');
        await fn({ gameId, ...settings });
      } catch (error: unknown) {
        setErrorMessage(lobbyErrorMessage(error, "Couldn't update the game settings."));
      }
    },
    [game, currentUserId, gameId],
  );

  return {
    game,
    players,
    errorMessage,
    isStartingGame,
    isGameDisbanded,
    isGameStarted,
    isHost,
    canStartGame,
    minPlayers,
    startGame,
    leaveGame,
    updatePlayerColor,
    updateCommanderName,
    updateGameSettings,
  };
}
