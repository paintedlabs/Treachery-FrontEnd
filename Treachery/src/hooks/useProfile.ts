import { useState, useEffect, useCallback } from 'react';
import { TreacheryUser, Game, Role } from '@/models/types';
import * as firestoreService from '@/services/firestore';

export interface GameStats {
  totalGames: number;
  wins: number;
  losses: number;
  roleBreakdown: Partial<Record<Role, number>>;
  winRateText: string;
}

interface UseProfileReturn {
  user: TreacheryUser | null;
  gameStats: GameStats | null;
  errorMessage: string | null;
  isLoading: boolean;
  isSaving: boolean;
  saveName: (newName: string) => Promise<void>;
  refresh: () => Promise<void>;
}

export function useProfile(userId: string | null): UseProfileReturn {
  const [user, setUser] = useState<TreacheryUser | null>(null);
  const [gameStats, setGameStats] = useState<GameStats | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);

  const loadData = useCallback(async () => {
    if (!userId) return;
    setIsLoading(true);
    setErrorMessage(null);

    // Fetch user first — this should always work
    try {
      const fetchedUser = await firestoreService.getUser(userId);
      setUser(fetchedUser);
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to load profile.');
      setIsLoading(false);
      return;
    }

    // Fetch game stats separately — this query needs a composite index
    // and may fail on first run
    try {
      const games = await firestoreService.getFinishedGames(userId);

      let wins = 0;
      let losses = 0;
      const roleBreakdown: Partial<Record<Role, number>> = {};

      for (const game of games) {
        const players = await firestoreService.getPlayers(game.id);
        const myPlayer = players.find((p) => p.user_id === userId);
        if (!myPlayer?.role) continue;

        roleBreakdown[myPlayer.role] = (roleBreakdown[myPlayer.role] ?? 0) + 1;

        if (game.winning_team) {
          const winRole = game.winning_team as Role;
          const didWin =
            winRole === 'leader'
              ? myPlayer.role === 'leader' || myPlayer.role === 'guardian'
              : myPlayer.role === winRole;
          if (didWin) wins++;
          else losses++;
        }
      }

      const totalGames = games.length;
      const winRateText =
        totalGames > 0 ? `${Math.round((wins / totalGames) * 100)}%` : '—';

      setGameStats({ totalGames, wins, losses, roleBreakdown, winRateText });
    } catch (error: any) {
      console.warn('Failed to load game stats:', error.message);
      // Still show the profile even if stats fail — set empty stats
      setGameStats({ totalGames: 0, wins: 0, losses: 0, roleBreakdown: {}, winRateText: '—' });
    }

    setIsLoading(false);
  }, [userId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const saveName = useCallback(
    async (newName: string) => {
      if (!user) return;
      const trimmed = newName.trim();
      if (!trimmed) return;
      setIsSaving(true);
      setErrorMessage(null);

      try {
        const updatedUser: TreacheryUser = { ...user, display_name: trimmed };
        await firestoreService.updateUser(updatedUser);
        setUser(updatedUser);
      } catch (error: any) {
        setErrorMessage(error.message || 'Failed to save name.');
      }
      setIsSaving(false);
    },
    [user]
  );

  return {
    user,
    gameStats,
    errorMessage,
    isLoading,
    isSaving,
    saveName,
    refresh: loadData,
  };
}
