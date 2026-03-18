import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  FlatList,
  Alert,
  Platform,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '@/hooks/useAuth';
import { useGameBoard } from '@/hooks/useGameBoard';
import { IdentityCardHeader } from '@/components/IdentityCardHeader';
import { IdentityCardDetail } from '@/components/IdentityCardDetail';
import { PlaneCardBanner } from '@/components/PlaneCardBanner';
import { PlaneCardDetail } from '@/components/PlaneCardDetail';
import { PlanarDieBar } from '@/components/PlanarDieBar';
import { ChaoticAetherBanner } from '@/components/ChaoticAetherBanner';
import { InterplanarTunnelPicker } from '@/components/InterplanarTunnelPicker';
import { PlayerRow } from '@/components/PlayerRow';
import { ErrorBanner } from '@/components/ErrorBanner';
import { LoadingScreen } from '@/components/LoadingScreen';
import { ConnectionBanner } from '@/components/ConnectionBanner';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES, ROLE_WIN_CONDITIONS } from '@/constants/roles';
import { Player } from '@/models/types';
import { colors, spacing, fonts } from '@/constants/theme';

export default function GameBoardScreen() {
  const { gameId } = useLocalSearchParams<{ gameId: string }>();
  const router = useRouter();
  const { currentUserId } = useAuth();

  const {
    game,
    players,
    errorMessage,
    isGameUnavailable,
    isGameFinished,
    currentPlayer,
    currentIdentityCard,
    isPending,
    adjustLife,
    unveilCurrentPlayer,
    eliminateAndLeave,
    canSeeRole,
    identityCard,
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
  } = useGameBoard(gameId!, currentUserId);

  const [showCardDetail, setShowCardDetail] = useState(false);
  const [showPlaneDetail, setShowPlaneDetail] = useState(false);
  const [inspectedPlayer, setInspectedPlayer] = useState<Player | null>(null);
  const [showUnveilConfirm, setShowUnveilConfirm] = useState(false);

  const isHost = game?.host_id === currentUserId;

  // Derive last roller name from players
  const lastRollerName = (() => {
    const rollerId = game?.planechase?.last_die_roller_id;
    if (!rollerId) return null;
    const roller = players.find((p) => p.user_id === rollerId);
    return roller?.display_name ?? null;
  })();

  // On web, intercept browser back button — push user back into the game
  useEffect(() => {
    if (Platform.OS !== 'web') return;

    // Push a duplicate history entry so pressing back stays on this page
    window.history.pushState(null, '', window.location.href);

    const handlePopState = () => {
      // Re-push so the user can't back out
      window.history.pushState(null, '', window.location.href);
    };

    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, []);

  // Navigate to game over when finished
  useEffect(() => {
    if (isGameFinished) {
      router.replace({
        pathname: '/(app)/game-over/[gameId]',
        params: { gameId: gameId! },
      });
    }
  }, [isGameFinished, gameId, router]);

  // Handle game unavailable
  useEffect(() => {
    if (isGameUnavailable) {
      Alert.alert('Game Unavailable', 'This game is no longer available.', [
        { text: 'OK', onPress: () => router.replace('/(app)') },
      ]);
    }
  }, [isGameUnavailable, router]);

  const navigateToGameOver = () => {
    router.replace({
      pathname: '/(app)/game-over/[gameId]',
      params: { gameId: gameId! },
    });
  };

  const handleForfeit = () => {
    if (Platform.OS === 'web') {
      const confirmed = window.confirm('Forfeit Game?\n\nYou will be eliminated from the game. This cannot be undone.');
      if (confirmed) {
        eliminateAndLeave().then(navigateToGameOver);
      }
    } else {
      Alert.alert(
        'Forfeit Game?',
        'You will be eliminated from the game. This cannot be undone.',
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Forfeit',
            style: 'destructive',
            onPress: async () => {
              await eliminateAndLeave();
              navigateToGameOver();
            },
          },
        ]
      );
    }
  };

  const handleUnveil = () => {
    const roleName = currentPlayer?.role ? ROLE_DISPLAY_NAMES[currentPlayer.role] : '';
    const cardName = currentIdentityCard?.name ?? '';
    if (Platform.OS === 'web') {
      const confirmed = window.confirm(
        `Unveil your identity?\n\nThis will reveal your role (${roleName}) and card (${cardName}) to all players. This cannot be undone.`
      );
      if (confirmed) unveilCurrentPlayer();
    } else {
      Alert.alert(
        'Unveil your identity?',
        `This will reveal your role (${roleName}) and card (${cardName}) to all players. This cannot be undone.`,
        [
          { text: 'Cancel', style: 'cancel' },
          { text: 'Unveil', onPress: () => unveilCurrentPlayer() },
        ]
      );
    }
  };

  const handleEndGame = () => {
    if (Platform.OS === 'web') {
      const confirmed = window.confirm('End Game?\n\nThis will end the game for all players.');
      if (confirmed) endGame();
    } else {
      Alert.alert(
        'End Game?',
        'This will end the game for all players.',
        [
          { text: 'Cancel', style: 'cancel' },
          { text: 'End Game', style: 'destructive', onPress: () => endGame() },
        ]
      );
    }
  };

  if (isGameUnavailable) {
    return (
      <View style={styles.centerContainer}>
        <Ionicons name="wifi" size={48} color={colors.warning} />
        <Text style={styles.unavailableTitle}>Game Unavailable</Text>
        <Text style={styles.unavailableText}>
          This game is no longer available.
        </Text>
        <TouchableOpacity
          style={styles.primaryButton}
          onPress={() => router.replace('/(app)')}
          accessibilityLabel="Return to home"
          accessibilityRole="button"
        >
          <Text style={styles.buttonText}>Return to Home</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (players.length === 0) {
    return <LoadingScreen message="Loading game..." />;
  }

  const inspectedCard = inspectedPlayer ? identityCard(inspectedPlayer) : undefined;

  return (
    <View style={styles.container}>
      <ConnectionBanner />

      {/* Identity card header — only when treachery active */}
      {isTreacheryActive && currentIdentityCard && currentPlayer && (
        <IdentityCardHeader
          card={currentIdentityCard}
          player={currentPlayer}
          onPress={() => setShowCardDetail(true)}
        />
      )}

      {/* Plane card banner — only when planechase active and not own-deck */}
      {isPlanechaseActive && !isOwnDeckMode && currentPlane && (
        <PlaneCardBanner
          planeCard={currentPlane}
          secondaryPlaneCard={secondaryPlane}
          onPress={() => setShowPlaneDetail(true)}
        />
      )}

      {/* Chaotic Aether warning banner */}
      {isPlanechaseActive && isChaoticAetherActive && (
        <ChaoticAetherBanner />
      )}

      {/* Ornate divider */}
      <View style={styles.ornateDividerRow}>
        <View style={styles.ornateLine} />
        <Text style={styles.ornateDiamond}>&#9670;</Text>
        <View style={styles.ornateLine} />
      </View>

      {/* Player list — always shown */}
      <FlatList
        data={players}
        keyExtractor={(p) => p.id}
        renderItem={({ item }) => (
          <PlayerRow
            player={item}
            isCurrentUser={item.user_id === currentUserId}
            canSeeRole={isTreacheryActive ? canSeeRole(item) : false}
            isUnveiledOrLeader={item.is_unveiled || item.role === 'leader'}
            onAdjustLife={(amount) => adjustLife(item.id, amount)}
            onViewCard={() => setInspectedPlayer(item)}
            isDisabled={false}
          />
        )}
        style={styles.list}
      />

      {errorMessage && <ErrorBanner message={errorMessage} />}

      {/* Spectator overlay for eliminated players */}
      {currentPlayer?.is_eliminated && (
        <View style={styles.spectatorBar}>
          <View style={styles.spectatorBanner}>
            <Ionicons name="skull" size={20} color={colors.error} />
            <Text style={styles.spectatorTitle}>You've Been Eliminated</Text>
          </View>
          <Text style={styles.spectatorSubtitle}>
            You're now spectating. Watch the game unfold or leave.
          </Text>
          <TouchableOpacity
            style={styles.spectatorLeaveButton}
            onPress={navigateToGameOver}
            accessibilityLabel="Leave game"
            accessibilityRole="button"
          >
            <Text style={styles.spectatorLeaveText}>Leave Game</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Planar die bar — only when planechase active */}
      {isPlanechaseActive && currentPlayer && !currentPlayer.is_eliminated && (
        <PlanarDieBar
          cost={dieRollCost}
          isRolling={isRollingDie}
          lastResult={dieRollResult}
          lastRollerName={lastRollerName}
          onRoll={rollDie}
        />
      )}

      {/* Action bar (unveil/win) — only when treachery active */}
      {isTreacheryActive && currentPlayer && !currentPlayer.is_eliminated && (
        <View style={styles.actionBar}>
          {!currentPlayer.is_unveiled &&
            currentPlayer.role !== 'leader' && (
              <TouchableOpacity
                style={[
                  styles.unveilButton,
                  {
                    backgroundColor: currentPlayer.role
                      ? ROLE_COLORS[currentPlayer.role]
                      : colors.primary,
                  },
                  isPending && styles.buttonDisabled,
                ]}
                onPress={handleUnveil}
                disabled={isPending}
                accessibilityLabel="Unveil identity"
                accessibilityRole="button"
                accessibilityHint="Reveals your role and card to all players"
              >
                <Text style={styles.unveilButtonText}>Unveil Identity</Text>
              </TouchableOpacity>
            )}

          {currentPlayer.role && (
            <View style={styles.winConditionBox}>
              <Text style={styles.winConditionLabel}>Win Condition</Text>
              <Text style={styles.winConditionText}>
                {ROLE_WIN_CONDITIONS[currentPlayer.role]}
              </Text>
            </View>
          )}
        </View>
      )}

      {/* Forfeit button — only when treachery active */}
      {isTreacheryActive && currentPlayer && !currentPlayer.is_eliminated && (
        <TouchableOpacity
          style={[styles.forfeitButton, isPending && { opacity: 0.5 }]}
          onPress={handleForfeit}
          disabled={isPending}
          accessibilityLabel="Forfeit"
          accessibilityRole="button"
          accessibilityHint="Eliminates you from the game"
        >
          <Ionicons name="flag" size={16} color={colors.warning} />
          <Text style={styles.forfeitText}>Forfeit</Text>
        </TouchableOpacity>
      )}

      {/* End Game button — only when NOT treachery (host only) */}
      {!isTreacheryActive && isHost && currentPlayer && !currentPlayer.is_eliminated && (
        <TouchableOpacity
          style={[styles.endGameButton, isPending && { opacity: 0.5 }]}
          onPress={handleEndGame}
          disabled={isPending}
          accessibilityLabel="End game"
          accessibilityRole="button"
          accessibilityHint="Ends the game for all players"
        >
          <Ionicons name="stop-circle" size={16} color={colors.error} />
          <Text style={styles.endGameText}>End Game</Text>
        </TouchableOpacity>
      )}

      {/* Identity card detail modal */}
      {isTreacheryActive && currentIdentityCard && currentPlayer && (
        <IdentityCardDetail
          card={currentIdentityCard}
          player={currentPlayer}
          visible={showCardDetail}
          onClose={() => setShowCardDetail(false)}
        />
      )}

      {/* Plane card detail modal */}
      {isPlanechaseActive && currentPlane && (
        <PlaneCardDetail
          planeCard={currentPlane}
          visible={showPlaneDetail}
          onClose={() => setShowPlaneDetail(false)}
        />
      )}

      {/* Inspected player card modal */}
      {inspectedCard && inspectedPlayer && (
        <IdentityCardDetail
          card={inspectedCard}
          player={inspectedPlayer}
          visible={!!inspectedPlayer}
          onClose={() => setInspectedPlayer(null)}
        />
      )}

      {/* Interplanar Tunnel picker modal */}
      {tunnelOptions && (
        <InterplanarTunnelPicker
          options={tunnelOptions}
          visible={tunnelOptions !== null}
          onSelect={selectTunnelPlane}
          isSelecting={isPending}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  centerContainer: {
    flex: 1,
    backgroundColor: colors.background,
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.lg,
    gap: 12,
  },
  ornateDividerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.lg,
    paddingVertical: 4,
    gap: 8,
  },
  ornateLine: {
    flex: 1,
    height: 1,
    backgroundColor: colors.border,
  },
  ornateDiamond: {
    color: colors.primary,
    fontSize: 8,
  },
  list: {
    flex: 1,
  },
  actionBar: {
    padding: spacing.lg,
    alignItems: 'center',
    gap: 12,
    borderTopWidth: 1,
    borderTopColor: colors.divider,
  },
  unveilButton: {
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    width: '100%',
  },
  unveilButtonText: {
    color: '#0d0b1a',
    fontSize: 16,
    fontWeight: '700',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  primaryButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    minWidth: 200,
  },
  buttonText: {
    color: '#0d0b1a',
    fontSize: 16,
    fontWeight: '700',
  },
  winConditionBox: {
    alignItems: 'center',
    gap: 4,
  },
  winConditionLabel: {
    color: colors.primary,
    fontSize: 10,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  winConditionText: {
    color: colors.textSecondary,
    fontSize: 11,
    textAlign: 'center',
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
  spectatorBar: {
    borderTopWidth: 1,
    borderTopColor: colors.error,
    backgroundColor: 'rgba(196, 60, 60, 0.1)',
    padding: spacing.lg,
    alignItems: 'center',
    gap: 8,
  },
  spectatorBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  spectatorTitle: {
    color: colors.error,
    fontSize: 18,
    fontWeight: '700',
    fontFamily: fonts.serif,
  },
  spectatorSubtitle: {
    color: colors.textSecondary,
    fontSize: 13,
    textAlign: 'center',
    fontStyle: 'italic',
  },
  spectatorLeaveButton: {
    borderWidth: 1,
    borderColor: colors.error,
    borderRadius: 8,
    paddingVertical: 10,
    paddingHorizontal: 24,
    marginTop: 4,
  },
  spectatorLeaveText: {
    color: colors.error,
    fontSize: 14,
    fontWeight: '600',
  },
  forfeitButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingBottom: spacing.lg,
  },
  forfeitText: {
    color: colors.warning,
    fontSize: 14,
  },
  endGameButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingBottom: spacing.lg,
  },
  endGameText: {
    color: colors.error,
    fontSize: 14,
    fontWeight: '600',
  },
  unavailableTitle: {
    color: colors.text,
    fontSize: 20,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  unavailableText: {
    color: colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
  },
});
