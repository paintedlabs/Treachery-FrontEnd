import { useState, useEffect, useCallback } from 'react';
import { Game, Player } from '@/models/types';
import * as firestoreService from '@/services/firestore';

interface UseGameHistoryReturn {
  games: Game[];
  gamePlayers: Record<string, Player[]>;
  isLoading: boolean;
  errorMessage: string | null;
  refresh: () => Promise<void>;
}

export function useGameHistory(userId: string | null): UseGameHistoryReturn {
  const [games, setGames] = useState<Game[]>([]);
  const [gamePlayers, setGamePlayers] = useState<Record<string, Player[]>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const loadHistory = useCallback(async () => {
    if (!userId) return;
    setIsLoading(true);
    setErrorMessage(null);

    try {
      const fetchedGames = await firestoreService.getFinishedGames(userId);
      setGames(fetchedGames);

      const playerMap: Record<string, Player[]> = {};
      for (const game of fetchedGames) {
        playerMap[game.id] = await firestoreService.getPlayers(game.id);
      }
      setGamePlayers(playerMap);
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to load history.');
    }
    setIsLoading(false);
  }, [userId]);

  useEffect(() => {
    loadHistory();
  }, [loadHistory]);

  return {
    games,
    gamePlayers,
    isLoading,
    errorMessage,
    refresh: loadHistory,
  };
}
