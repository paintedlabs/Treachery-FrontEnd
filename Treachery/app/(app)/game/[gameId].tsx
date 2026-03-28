import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  FlatList,
  Alert,
  Platform,
  Modal,
  ScrollView,
  Image,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '@/hooks/useAuth';
import { useGameBoard } from '@/hooks/useGameBoard';
import { useResponsive } from '@/hooks/useResponsive';
import { IdentityCardHeader } from '@/components/IdentityCardHeader';
import { IdentityCardDetail } from '@/components/IdentityCardDetail';
import { PlaneCardBanner } from '@/components/PlaneCardBanner';
import { PlaneCardDetail } from '@/components/PlaneCardDetail';
import { ChaoticAetherBanner } from '@/components/ChaoticAetherBanner';
import { InterplanarTunnelPicker } from '@/components/InterplanarTunnelPicker';
import { PlayerRow } from '@/components/PlayerRow';
import { ErrorBanner } from '@/components/ErrorBanner';
import { LoadingScreen } from '@/components/LoadingScreen';
import { ConnectionBanner } from '@/components/ConnectionBanner';
import { ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { Player } from '@/models/types';
import { colors, spacing, fonts } from '@/constants/theme';

export default function GameBoardScreen() {
  const { gameId } = useLocalSearchParams<{ gameId: string }>();
  const router = useRouter();
  const { currentUserId } = useAuth();
  const { isDesktop } = useResponsive();

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
    updatePlayerColor,
    alivePlayers,
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
    endGame,
  } = useGameBoard(gameId!, currentUserId);

  const [showCardDetail, setShowCardDetail] = useState(false);
  const [showPlaneDetail, setShowPlaneDetail] = useState(false);
  const [inspectedPlayer, setInspectedPlayer] = useState<Player | null>(null);
  const [showWinnerSelection, setShowWinnerSelection] = useState(false);
  const [selectedWinners, setSelectedWinners] = useState<Set<string>>(new Set());

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
      const confirmed = window.confirm(
        'Forfeit Game?\n\nYou will be eliminated from the game. This cannot be undone.',
      );
      if (confirmed) {
        eliminateAndLeave().then(navigateToGameOver);
      }
    } else {
      Alert.alert('Forfeit Game?', 'You will be eliminated from the game. This cannot be undone.', [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Forfeit',
          style: 'destructive',
          onPress: async () => {
            await eliminateAndLeave();
            navigateToGameOver();
          },
        },
      ]);
    }
  };

  const handleUnveil = () => {
    const roleName = currentPlayer?.role ? ROLE_DISPLAY_NAMES[currentPlayer.role] : '';
    const cardName = currentIdentityCard?.name ?? '';
    if (Platform.OS === 'web') {
      const confirmed = window.confirm(
        `Unveil your identity?\n\nThis will reveal your role (${roleName}) and card (${cardName}) to all players. This cannot be undone.`,
      );
      if (confirmed) unveilCurrentPlayer();
    } else {
      Alert.alert(
        'Unveil your identity?',
        `This will reveal your role (${roleName}) and card (${cardName}) to all players. This cannot be undone.`,
        [
          { text: 'Cancel', style: 'cancel' },
          { text: 'Unveil', onPress: () => unveilCurrentPlayer() },
        ],
      );
    }
  };

  const handleEndGame = () => {
    setSelectedWinners(new Set());
    setShowWinnerSelection(true);
  };

  const toggleWinner = (userId: string) => {
    setSelectedWinners((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) {
        next.delete(userId);
      } else {
        next.add(userId);
      }
      return next;
    });
  };

  const confirmEndGame = () => {
    setShowWinnerSelection(false);
    const winners = selectedWinners.size > 0 ? Array.from(selectedWinners) : undefined;
    endGame(winners);
  };

  if (isGameUnavailable) {
    return (
      <View style={styles.centerContainer}>
        <Ionicons name="wifi" size={48} color={colors.warning} />
        <Text style={styles.unavailableTitle}>Game Unavailable</Text>
        <Text style={styles.unavailableText}>This game is no longer available.</Text>
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
      {/* Player color background tint */}
      {currentPlayer?.player_color && (
        <View
          style={[
            StyleSheet.absoluteFill,
            { backgroundColor: currentPlayer.player_color, opacity: 0.15 },
          ]}
          pointerEvents="none"
        />
      )}

      <ConnectionBanner />

      <View style={isDesktop ? styles.desktopRow : styles.mobileColumn}>
        {/* ── Desktop sidebar ── */}
        {isDesktop && (
          <ScrollView style={styles.sidebar} contentContainerStyle={styles.sidebarContent}>
            {isTreacheryActive && currentIdentityCard && currentPlayer && (
              <IdentityCardHeader
                card={currentIdentityCard}
                player={currentPlayer}
                onPress={() => setShowCardDetail(true)}
              />
            )}

            {isPlanechaseActive && !isOwnDeckMode && currentPlane && (
              <PlaneCardBanner
                planeCard={currentPlane}
                secondaryPlaneCard={secondaryPlane}
                onPress={() => setShowPlaneDetail(true)}
                dieCost={dieRollCost}
                isRolling={isRollingDie}
                onRollDie={currentPlayer && !currentPlayer.is_eliminated ? rollDie : undefined}
                lastDieResult={dieRollResult}
                lastRollerName={lastRollerName}
              />
            )}

            {isPlanechaseActive && isChaoticAetherActive && <ChaoticAetherBanner />}

            {/* Always-visible plane card image (rotated 90° clockwise) */}
            {isPlanechaseActive && !isOwnDeckMode && currentPlane?.image_uri && (
              <TouchableOpacity
                style={styles.sidebarImageContainer}
                onPress={() => setShowPlaneDetail(true)}
                activeOpacity={0.8}
                accessibilityLabel={`View ${currentPlane.name} details`}
                accessibilityRole="button"
              >
                <Image
                  source={{ uri: currentPlane.image_uri }}
                  style={styles.sidebarPlaneImage}
                  resizeMode="contain"
                />
              </TouchableOpacity>
            )}

            <View style={{ flex: 1 }} />

            {isTreacheryActive && currentPlayer && !currentPlayer.is_eliminated && (
              <View style={styles.actionBar}>
                {!currentPlayer.is_unveiled && currentPlayer.role !== 'leader' && (
                  <TouchableOpacity
                    style={[styles.unveilButton, isPending && styles.buttonDisabled]}
                    onPress={handleUnveil}
                    disabled={isPending}
                    accessibilityLabel="Unveil identity"
                    accessibilityRole="button"
                    accessibilityHint="Reveals your role and card to all players"
                  >
                    <Text style={styles.unveilButtonText}>Unveil Identity</Text>
                  </TouchableOpacity>
                )}
              </View>
            )}

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
          </ScrollView>
        )}

        {/* ── Main content area ── */}
        <View style={isDesktop ? styles.mainContent : styles.mobileColumn}>
          {/* Mobile-only: identity card header */}
          {!isDesktop && isTreacheryActive && currentIdentityCard && currentPlayer && (
            <IdentityCardHeader
              card={currentIdentityCard}
              player={currentPlayer}
              onPress={() => setShowCardDetail(true)}
            />
          )}

          {/* Mobile-only: plane card banner */}
          {!isDesktop && isPlanechaseActive && !isOwnDeckMode && currentPlane && (
            <PlaneCardBanner
              planeCard={currentPlane}
              secondaryPlaneCard={secondaryPlane}
              onPress={() => setShowPlaneDetail(true)}
              dieCost={dieRollCost}
              isRolling={isRollingDie}
              onRollDie={currentPlayer && !currentPlayer.is_eliminated ? rollDie : undefined}
              lastDieResult={dieRollResult}
              lastRollerName={lastRollerName}
            />
          )}

          {/* Mobile-only: chaotic aether */}
          {!isDesktop && isPlanechaseActive && isChaoticAetherActive && <ChaoticAetherBanner />}

          {/* Ornate divider */}
          <View style={styles.ornateDividerRow}>
            <View style={styles.ornateLine} />
            <Text style={styles.ornateDiamond}>&#9670;</Text>
            <View style={styles.ornateLine} />
          </View>

          {/* Player list */}
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
                onColorChange={item.user_id === currentUserId ? updatePlayerColor : undefined}
                playerColor={item.player_color}
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
                <Text style={styles.spectatorTitle}>You&apos;ve Been Eliminated</Text>
              </View>
              <Text style={styles.spectatorSubtitle}>
                You&apos;re now spectating. Watch the game unfold or leave.
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

          {/* Mobile-only: action bar and buttons */}
          {!isDesktop && isTreacheryActive && currentPlayer && !currentPlayer.is_eliminated && (
            <View style={styles.actionBar}>
              {!currentPlayer.is_unveiled && currentPlayer.role !== 'leader' && (
                <TouchableOpacity
                  style={[styles.unveilButton, isPending && styles.buttonDisabled]}
                  onPress={handleUnveil}
                  disabled={isPending}
                  accessibilityLabel="Unveil identity"
                  accessibilityRole="button"
                  accessibilityHint="Reveals your role and card to all players"
                >
                  <Text style={styles.unveilButtonText}>Unveil Identity</Text>
                </TouchableOpacity>
              )}
            </View>
          )}

          {!isDesktop && isTreacheryActive && currentPlayer && !currentPlayer.is_eliminated && (
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

          {!isDesktop && !isTreacheryActive && isHost && currentPlayer && !currentPlayer.is_eliminated && (
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
        </View>
      </View>

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

      {/* Winner Selection Modal */}
      <Modal
        visible={showWinnerSelection}
        transparent
        animationType="fade"
        onRequestClose={() => setShowWinnerSelection(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>End Game</Text>
            <Text style={styles.modalSubtitle}>
              Select the winner(s) of this game for ELO tracking.
            </Text>

            <ScrollView style={styles.winnerList}>
              {alivePlayers.map((player) => (
                <TouchableOpacity
                  key={player.user_id}
                  style={styles.winnerRow}
                  onPress={() => toggleWinner(player.user_id)}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: selectedWinners.has(player.user_id) }}
                >
                  <View
                    style={[
                      styles.winnerCheckbox,
                      selectedWinners.has(player.user_id) && styles.winnerCheckboxSelected,
                    ]}
                  >
                    {selectedWinners.has(player.user_id) && (
                      <Ionicons name="checkmark" size={14} color="#0d0b1a" />
                    )}
                  </View>
                  <View style={styles.winnerInfo}>
                    <View style={styles.winnerNameRow}>
                      {player.player_color && (
                        <View
                          style={[styles.winnerColorDot, { backgroundColor: player.player_color }]}
                        />
                      )}
                      <Text style={styles.winnerName}>{player.display_name}</Text>
                    </View>
                    {player.commander_name && (
                      <Text style={styles.winnerCommander}>{player.commander_name}</Text>
                    )}
                  </View>
                </TouchableOpacity>
              ))}
            </ScrollView>

            <Text style={styles.modalNote}>
              You can skip winner selection — ELO won&apos;t be updated.
            </Text>

            <TouchableOpacity
              style={[styles.modalEndButton, isPending && styles.buttonDisabled]}
              onPress={confirmEndGame}
              disabled={isPending}
              accessibilityLabel="End game"
              accessibilityRole="button"
            >
              <Text style={styles.modalEndButtonText}>End Game</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.modalCancelButton}
              onPress={() => setShowWinnerSelection(false)}
              accessibilityLabel="Cancel"
              accessibilityRole="button"
            >
              <Text style={styles.modalCancelText}>Cancel</Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  desktopRow: {
    flex: 1,
    flexDirection: 'row',
  },
  mobileColumn: {
    flex: 1,
  },
  sidebar: {
    width: 320,
    borderRightWidth: 1,
    borderRightColor: colors.divider,
    backgroundColor: colors.surface,
  },
  sidebarContent: {
    flexGrow: 1,
  },
  mainContent: {
    flex: 1,
  },
  sidebarImageContainer: {
    margin: 12,
    borderRadius: 8,
    overflow: 'hidden',
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sidebarPlaneImage: {
    width: '73%',
    aspectRatio: 457 / 626,
    transform: [{ rotate: '90deg' }],
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
    backgroundColor: colors.primary,
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
  // Winner Selection Modal
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.lg,
  },
  modalContent: {
    backgroundColor: colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
    width: '100%',
    maxWidth: 400,
    maxHeight: '80%',
  },
  modalTitle: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '700',
    fontFamily: fonts.serif,
    textAlign: 'center',
    marginBottom: 4,
  },
  modalSubtitle: {
    color: colors.textSecondary,
    fontSize: 13,
    textAlign: 'center',
    marginBottom: spacing.lg,
  },
  winnerList: {
    maxHeight: 300,
  },
  winnerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 4,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
    gap: 12,
  },
  winnerCheckbox: {
    width: 24,
    height: 24,
    borderRadius: 6,
    borderWidth: 2,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  winnerCheckboxSelected: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  winnerInfo: {
    flex: 1,
    gap: 2,
  },
  winnerNameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  winnerColorDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
  winnerName: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
  winnerCommander: {
    color: colors.textSecondary,
    fontSize: 13,
    fontStyle: 'italic',
    fontFamily: fonts.serif,
  },
  modalNote: {
    color: colors.textTertiary,
    fontSize: 11,
    textAlign: 'center',
    fontStyle: 'italic',
    marginTop: spacing.md,
    marginBottom: spacing.lg,
  },
  modalEndButton: {
    backgroundColor: colors.error,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    marginBottom: spacing.sm,
  },
  modalEndButtonText: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '700',
  },
  modalCancelButton: {
    padding: 10,
    alignItems: 'center',
  },
  modalCancelText: {
    color: colors.textSecondary,
    fontSize: 14,
  },
});
