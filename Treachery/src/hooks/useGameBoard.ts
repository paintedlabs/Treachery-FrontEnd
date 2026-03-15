import { useState, useEffect, useCallback, useRef } from 'react';
import { Game, Player, Role, IdentityCard } from '@/models/types';
import * as firestoreService from '@/services/firestore';
import { getCard } from '@/services/cardDatabase';

interface UseGameBoardReturn {
  game: Game | null;
  players: Player[];
  errorMessage: string | null;
  isGameUnavailable: boolean;
  isGameFinished: boolean;
  winningTeam: Role | null;
  currentPlayer: Player | null;
  currentIdentityCard: IdentityCard | undefined;
  alivePlayers: Player[];
  adjustLife: (playerId: string, amount: number) => Promise<void>;
  unveilCurrentPlayer: () => Promise<void>;
  eliminateAndLeave: () => Promise<void>;
  canSeeRole: (player: Player) => boolean;
  identityCard: (player: Player) => IdentityCard | undefined;
}

export function useGameBoard(gameId: string, currentUserId: string | null): UseGameBoardReturn {
  const [game, setGame] = useState<Game | null>(null);
  const [players, setPlayers] = useState<Player[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isGameUnavailable, setIsGameUnavailable] = useState(false);
  const hasReceivedFirstSnapshot = useRef(false);

  useEffect(() => {
    const unsubGame = firestoreService.listenToGame(gameId, (g) => {
      if (g === null && hasReceivedFirstSnapshot.current) {
        setIsGameUnavailable(true);
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

  const currentPlayer = players.find((p) => p.user_id === currentUserId) ?? null;

  const currentIdentityCard = currentPlayer?.identity_card_id
    ? getCard(currentPlayer.identity_card_id)
    : undefined;

  const isGameFinished = game?.state === 'finished';

  const winningTeam: Role | null = (game?.winning_team as Role) ?? null;

  const alivePlayers = players.filter((p) => !p.is_eliminated);

  const checkWinConditions = useCallback(
    async (currentPlayers: Player[], currentGame: Game | null) => {
      const alive = currentPlayers.filter((p) => !p.is_eliminated);

      // Traitor wins: last player standing and is a traitor
      if (alive.length === 1 && alive[0].role === 'traitor') {
        await endGame('traitor', currentGame);
        return;
      }

      const leaderAlive = alive.some((p) => p.role === 'leader');
      const assassinAlive = alive.some((p) => p.role === 'assassin');
      const traitorAlive = alive.some((p) => p.role === 'traitor');

      // Assassin wins: Leader eliminated AND at least 1 assassin survives
      if (!leaderAlive && assassinAlive) {
        await endGame('assassin', currentGame);
        return;
      }

      // Leader/Guardian wins: Leader alive + all assassins AND traitors eliminated
      if (leaderAlive && !assassinAlive && !traitorAlive) {
        await endGame('leader', currentGame);
        return;
      }

      // Edge: Leader dead + no assassins + no traitors
      if (!leaderAlive && !assassinAlive && !traitorAlive) {
        await endGame('assassin', currentGame);
        return;
      }
    },
    []
  );

  const endGame = async (winningRole: Role, currentGame: Game | null) => {
    if (!currentGame) return;
    const updatedGame: Game = {
      ...currentGame,
      state: 'finished',
      winning_team: winningRole,
    };
    try {
      await firestoreService.updateGame(updatedGame);
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to end game.');
    }
  };

  const adjustLife = useCallback(
    async (playerId: string, amount: number) => {
      const player = players.find((p) => p.id === playerId);
      if (!player || player.is_eliminated) return;
      setErrorMessage(null);

      let newLife = player.life_total + amount;
      let eliminated = false;

      if (newLife <= 0) {
        newLife = 0;
        eliminated = true;
      }

      const updatedPlayer: Player = {
        ...player,
        life_total: newLife,
        is_eliminated: eliminated,
      };

      try {
        await firestoreService.updatePlayer(updatedPlayer, gameId);

        if (eliminated) {
          // Use updated player list for win condition check
          const updatedPlayers = players.map((p) =>
            p.id === playerId ? updatedPlayer : p
          );
          await checkWinConditions(updatedPlayers, game);
        }
      } catch (error: any) {
        setErrorMessage(error.message || 'Failed to adjust life.');
      }
    },
    [players, gameId, game, checkWinConditions]
  );

  const unveilCurrentPlayer = useCallback(async () => {
    if (!currentPlayer || currentPlayer.is_unveiled) return;
    setErrorMessage(null);

    const updatedPlayer: Player = { ...currentPlayer, is_unveiled: true };

    try {
      await firestoreService.updatePlayer(updatedPlayer, gameId);
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to unveil.');
    }
  }, [currentPlayer, gameId]);

  const eliminateAndLeave = useCallback(async () => {
    if (!currentPlayer) return;
    setErrorMessage(null);

    const updatedPlayer: Player = {
      ...currentPlayer,
      is_eliminated: true,
      life_total: 0,
    };

    try {
      await firestoreService.updatePlayer(updatedPlayer, gameId);
      const updatedPlayers = players.map((p) =>
        p.id === currentPlayer.id ? updatedPlayer : p
      );
      await checkWinConditions(updatedPlayers, game);
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to forfeit.');
    }
  }, [currentPlayer, players, gameId, game, checkWinConditions]);

  const canSeeRole = useCallback(
    (player: Player): boolean => {
      if (player.user_id === currentUserId) return true;
      if (player.is_unveiled) return true;
      if (player.role === 'leader') return true;
      return false;
    },
    [currentUserId]
  );

  const identityCardFn = useCallback((player: Player): IdentityCard | undefined => {
    if (!player.identity_card_id) return undefined;
    return getCard(player.identity_card_id);
  }, []);

  return {
    game,
    players,
    errorMessage,
    isGameUnavailable,
    isGameFinished,
    winningTeam,
    currentPlayer,
    currentIdentityCard,
    alivePlayers,
    adjustLife,
    unveilCurrentPlayer,
    eliminateAndLeave,
    canSeeRole,
    identityCard: identityCardFn,
  };
}
