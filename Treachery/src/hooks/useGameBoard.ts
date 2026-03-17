import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { httpsCallable } from 'firebase/functions';
import { Game, Player, Role, IdentityCard, PlaneCard } from '@/models/types';
import * as firestoreService from '@/services/firestore';
import { functions } from '@/config/firebase';
import { getCard } from '@/services/cardDatabase';
import { getPlane } from '@/services/planeDatabase';

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
  isPending: boolean;
  adjustLife: (playerId: string, amount: number) => void;
  unveilCurrentPlayer: () => Promise<void>;
  eliminateAndLeave: () => Promise<void>;
  canSeeRole: (player: Player) => boolean;
  identityCard: (player: Player) => IdentityCard | undefined;
  // Planechase
  isPlanechaseActive: boolean;
  isTreacheryActive: boolean;
  isOwnDeckMode: boolean;
  currentPlane: PlaneCard | undefined;
  secondaryPlane: PlaneCard | undefined;
  isChaoticAetherActive: boolean;
  tunnelOptions: PlaneCard[] | null;
  selectTunnelPlane: (planeId: string) => Promise<void>;
  dieRollCost: number;
  dieRollResult: string | null;
  isRollingDie: boolean;
  rollDie: () => Promise<void>;
  resolvePhenomenon: () => Promise<void>;
  endGame: () => Promise<void>;
}

export function useGameBoard(gameId: string, currentUserId: string | null): UseGameBoardReturn {
  const [game, setGame] = useState<Game | null>(null);
  const [serverPlayers, setServerPlayers] = useState<Player[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isGameUnavailable, setIsGameUnavailable] = useState(false);
  const [isPending, setIsPending] = useState(false);
  const hasReceivedFirstSnapshot = useRef(false);

  // Planechase transient state
  const [dieRollResult, setDieRollResult] = useState<string | null>(null);
  const [isRollingDie, setIsRollingDie] = useState(false);
  const [tunnelOptions, setTunnelOptions] = useState<PlaneCard[] | null>(null);

  // Optimistic life deltas: playerId -> pending delta
  const lifeDeltasRef = useRef<Record<string, number>>({});
  const debounceTimersRef = useRef<Record<string, ReturnType<typeof setTimeout>>>({});
  const [lifeDeltas, setLifeDeltas] = useState<Record<string, number>>({});

  useEffect(() => {
    const unsubGame = firestoreService.listenToGame(gameId, (g) => {
      if (g === null && hasReceivedFirstSnapshot.current) {
        setIsGameUnavailable(true);
      }
      setGame(g);
      hasReceivedFirstSnapshot.current = true;
    });

    const unsubPlayers = firestoreService.listenToPlayers(gameId, (p) => {
      setServerPlayers(p);
      // Clear optimistic deltas for players whose server state has caught up
      setLifeDeltas((prev) => {
        const next = { ...prev };
        let changed = false;
        for (const id of Object.keys(next)) {
          if (next[id] === 0) {
            delete next[id];
            changed = true;
          }
        }
        return changed ? next : prev;
      });
    });

    return () => {
      unsubGame();
      unsubPlayers();
      // Clean up debounce timers
      for (const timer of Object.values(debounceTimersRef.current)) {
        clearTimeout(timer);
      }
    };
  }, [gameId]);

  // Merge server players with optimistic deltas
  const players = useMemo(() => {
    if (Object.keys(lifeDeltas).length === 0) return serverPlayers;
    return serverPlayers.map((p) => {
      const delta = lifeDeltas[p.id];
      if (delta === undefined || delta === 0) return p;
      return { ...p, life_total: Math.max(0, p.life_total + delta) };
    });
  }, [serverPlayers, lifeDeltas]);

  const currentPlayer = players.find((p) => p.user_id === currentUserId) ?? null;

  const currentIdentityCard = useMemo(
    () => currentPlayer?.identity_card_id ? getCard(currentPlayer.identity_card_id) : undefined,
    [currentPlayer?.identity_card_id]
  );

  const isGameFinished = game?.state === 'finished';

  const winningTeam: Role | null = (game?.winning_team as Role) ?? null;

  const alivePlayers = players.filter((p) => !p.is_eliminated);

  // ── Game mode computed booleans ──────────────────────────────────────

  const isPlanechaseActive = useMemo(() => {
    const mode = game?.game_mode;
    return mode === 'planechase' || mode === 'treachery_planechase';
  }, [game?.game_mode]);

  const isTreacheryActive = useMemo(() => {
    const mode = game?.game_mode;
    return mode === 'treachery' || mode === 'treachery_planechase';
  }, [game?.game_mode]);

  const isOwnDeckMode = useMemo(() => {
    return game?.planechase?.use_own_deck === true;
  }, [game?.planechase?.use_own_deck]);

  // ── Planechase derived state ─────────────────────────────────────────

  const currentPlane = useMemo(() => {
    const planeId = game?.planechase?.current_plane_id;
    if (!planeId) return undefined;
    return getPlane(planeId);
  }, [game?.planechase?.current_plane_id]);

  const secondaryPlane = useMemo(() => {
    const planeId = game?.planechase?.secondary_plane_id;
    if (!planeId) return undefined;
    return getPlane(planeId);
  }, [game?.planechase?.secondary_plane_id]);

  const isChaoticAetherActive = useMemo(() => {
    return game?.planechase?.chaotic_aether_active === true;
  }, [game?.planechase?.chaotic_aether_active]);

  const dieRollCost = useMemo(() => {
    // Cost starts at 0 for the first roll each turn, then increases by 1 each subsequent roll
    return game?.planechase?.die_roll_count ?? 0;
  }, [game?.planechase?.die_roll_count]);

  // ── All game actions now go through Cloud Functions ───────────────────
  // Win condition checking happens server-side automatically.

  const flushLifeDelta = useCallback(
    (playerId: string) => {
      const delta = lifeDeltasRef.current[playerId];
      if (!delta) return;

      // Clear the delta before sending so new taps start fresh
      lifeDeltasRef.current[playerId] = 0;
      setLifeDeltas((prev) => ({ ...prev, [playerId]: 0 }));

      const adjustLifeFn = httpsCallable(functions, 'adjustLife');
      adjustLifeFn({ gameId, playerId, amount: delta }).catch((error: any) => {
        // Revert: re-apply the delta that failed
        lifeDeltasRef.current[playerId] = (lifeDeltasRef.current[playerId] || 0) + delta;
        setLifeDeltas((prev) => ({
          ...prev,
          [playerId]: (prev[playerId] || 0) + delta,
        }));
        setErrorMessage(error.message || 'Failed to adjust life.');
      });
    },
    [gameId]
  );

  const adjustLife = useCallback(
    (playerId: string, amount: number) => {
      const player = serverPlayers.find((p) => p.id === playerId);
      if (!player || player.is_eliminated) return;
      setErrorMessage(null);

      // Accumulate optimistic delta
      lifeDeltasRef.current[playerId] = (lifeDeltasRef.current[playerId] || 0) + amount;
      setLifeDeltas((prev) => ({
        ...prev,
        [playerId]: (prev[playerId] || 0) + amount,
      }));

      // Debounce: reset timer and flush after 500ms of inactivity
      if (debounceTimersRef.current[playerId]) {
        clearTimeout(debounceTimersRef.current[playerId]);
      }
      debounceTimersRef.current[playerId] = setTimeout(() => {
        flushLifeDelta(playerId);
        delete debounceTimersRef.current[playerId];
      }, 500);
    },
    [serverPlayers, flushLifeDelta]
  );

  const unveilCurrentPlayer = useCallback(async () => {
    if (!currentPlayer || currentPlayer.is_unveiled || isPending) return;
    setErrorMessage(null);
    setIsPending(true);

    try {
      const unveilFn = httpsCallable(functions, 'unveilPlayer');
      await unveilFn({ gameId });
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to unveil.');
    } finally {
      setIsPending(false);
    }
  }, [currentPlayer, gameId, isPending]);

  const eliminateAndLeave = useCallback(async () => {
    if (!currentPlayer || isPending) return;
    setErrorMessage(null);
    setIsPending(true);

    try {
      const eliminateFn = httpsCallable(functions, 'eliminatePlayer');
      await eliminateFn({ gameId });
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to forfeit.');
    } finally {
      setIsPending(false);
    }
  }, [currentPlayer, gameId, isPending]);

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

  // ── Planechase actions ───────────────────────────────────────────────

  const rollDie = useCallback(async () => {
    if (isRollingDie || isPending) return;
    setErrorMessage(null);
    setIsRollingDie(true);
    setDieRollResult(null);

    try {
      const rollDieFn = httpsCallable<{ gameId: string }, { result: string }>(functions, 'rollPlanarDie');
      const response = await rollDieFn({ gameId });
      setDieRollResult(response.data.result);
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to roll die.');
    } finally {
      setIsRollingDie(false);
    }
  }, [gameId, isRollingDie, isPending]);

  const resolvePhenomenon = useCallback(async () => {
    if (isPending) return;
    setErrorMessage(null);
    setIsPending(true);

    try {
      const resolveFn = httpsCallable<{ gameId: string }, { type?: string; options?: string[] }>(functions, 'resolvePhenomenon');
      const response = await resolveFn({ gameId });

      if (response.data.type === 'choose' && response.data.options) {
        const planes = response.data.options
          .map((id) => getPlane(id))
          .filter((p): p is PlaneCard => p !== undefined);
        setTunnelOptions(planes);
      }
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to resolve phenomenon.');
    } finally {
      setIsPending(false);
    }
  }, [gameId, isPending]);

  const selectTunnelPlane = useCallback(async (planeId: string) => {
    if (isPending) return;
    setErrorMessage(null);
    setIsPending(true);

    try {
      const selectFn = httpsCallable(functions, 'selectPlane');
      await selectFn({ gameId, planeId });
      setTunnelOptions(null);
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to select plane.');
    } finally {
      setIsPending(false);
    }
  }, [gameId, isPending]);

  const endGame = useCallback(async () => {
    if (isPending) return;
    setErrorMessage(null);
    setIsPending(true);

    try {
      const endGameFn = httpsCallable(functions, 'endGame');
      await endGameFn({ gameId });
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to end game.');
    } finally {
      setIsPending(false);
    }
  }, [gameId, isPending]);

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
    isPending,
    adjustLife,
    unveilCurrentPlayer,
    eliminateAndLeave,
    canSeeRole,
    identityCard: identityCardFn,
    // Planechase
    isPlanechaseActive,
    isTreacheryActive,
    isOwnDeckMode,
    currentPlane,
    secondaryPlane,
    isChaoticAetherActive,
    tunnelOptions,
    selectTunnelPlane,
    dieRollCost,
    dieRollResult,
    isRollingDie,
    rollDie,
    resolvePhenomenon,
    endGame,
  };
}
