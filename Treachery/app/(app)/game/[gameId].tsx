import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useAuth } from '@/hooks/useAuth';
import { useGameBoard } from '@/hooks/useGameBoard';
import { useResponsive } from '@/hooks/useResponsive';
import { useWinnerSelection } from '@/hooks/useWinnerSelection';
import { useAbilityResolverModal } from '@/hooks/useAbilityResolverModal';
import { useBlockBrowserBack } from '@/hooks/useBlockBrowserBack';
import { useGameOverRedirect } from '@/hooks/useGameOverRedirect';
import { useGameConfirmDialog } from '@/hooks/useGameConfirmDialog';
import { IdentityCardHeader } from '@/components/IdentityCardHeader';
import { IdentityCardDetail } from '@/components/IdentityCardDetail';
import { PlaneCardDetail } from '@/components/PlaneCardDetail';
import { InterplanarTunnelPicker } from '@/components/InterplanarTunnelPicker';
import { PlanechaseStatus } from '@/components/PlanechaseStatus';
import { SidebarPlaneImage } from '@/components/SidebarPlaneImage';
import { GameActionButtons } from '@/components/GameActionButtons';
import { GameRoundTable } from '@/components/GameRoundTable';
import { GamePlayerList } from '@/components/GamePlayerList';
import { SpectatorBar } from '@/components/SpectatorBar';
import { WinnerSelectionModal } from '@/components/WinnerSelectionModal';
import { GameUnavailableScreen } from '@/components/GameUnavailableScreen';
import { ErrorBanner } from '@/components/ErrorBanner';
import { LoadingScreen } from '@/components/LoadingScreen';
import { ConnectionBanner } from '@/components/ConnectionBanner';
import { AbilityResolver } from '@/components/AbilityResolver';
import { ConfirmDialog } from '@/components/ConfirmDialog';
import { Player } from '@/models/types';
import { colors, spacing } from '@/constants/theme';

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
    renameCurrentPlayer,
    activePlayerId,
    advanceTurn,
    reorderSeats,
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
    resolvePhenomenon,
    endGame,
  } = useGameBoard(gameId!, currentUserId);

  const [showCardDetail, setShowCardDetail] = useState(false);
  const [showPlaneDetail, setShowPlaneDetail] = useState(false);
  const [inspectedPlayer, setInspectedPlayer] = useState<Player | null>(null);
  const winnerSelection = useWinnerSelection(endGame);
  const abilityResolver = useAbilityResolverModal(currentPlayer);

  const isHost = game?.host_id === currentUserId;

  // Derive last roller name from players
  const lastRollerName = (() => {
    const rollerId = game?.planechase?.last_die_roller_id;
    if (!rollerId) return null;
    const roller = players.find((p) => p.user_id === rollerId);
    return roller?.display_name ?? null;
  })();

  // On web, intercept browser back button — push user back into the game
  useBlockBrowserBack();
  // Navigate to game over when finished
  useGameOverRedirect(isGameFinished, gameId, router);

  const confirmDialog = useGameConfirmDialog({
    currentPlayer,
    currentIdentityCard,
    eliminateAndLeave,
    unveilCurrentPlayer,
  });

  // No Alert.alert for the unavailable case: it is a silent no-op on
  // react-native-web, and the full-screen fallback below already states it
  // and offers Return to Home on every platform.
  if (isGameUnavailable) {
    return <GameUnavailableScreen onReturnHome={() => router.replace('/(app)')} />;
  }

  if (players.length === 0) {
    return <LoadingScreen message="Loading game..." />;
  }

  const inspectedCard = inspectedPlayer ? identityCard(inspectedPlayer) : undefined;
  const isEliminatedSpectator = !!currentPlayer?.is_eliminated;
  // Spectators see the phenomenon card art instead of the resolver — the
  // server rejects their resolvePhenomenon anyway (failed-precondition).
  const showPhenomenonResolver =
    isPlanechaseActive &&
    !isOwnDeckMode &&
    !!currentPlane?.is_phenomenon &&
    !tunnelOptions &&
    !isEliminatedSpectator;

  // Each layout places these in a different spot: top / bottom of the sidebar
  // on desktop, top / bottom of the single column on mobile.
  const identityHeader = isTreacheryActive && currentIdentityCard && currentPlayer && (
    <IdentityCardHeader
      card={currentIdentityCard}
      player={currentPlayer}
      onPress={() => setShowCardDetail(true)}
    />
  );
  const planechaseStatus = (
    <PlanechaseStatus
      isPlanechaseActive={isPlanechaseActive}
      isOwnDeckMode={isOwnDeckMode}
      currentPlane={currentPlane}
      secondaryPlane={secondaryPlane}
      onPressPlane={() => setShowPlaneDetail(true)}
      dieRollCost={dieRollCost}
      isRollingDie={isRollingDie}
      onRollDie={currentPlayer && !currentPlayer.is_eliminated ? rollDie : undefined}
      dieRollResult={dieRollResult}
      lastRollerName={lastRollerName}
      isChaoticAetherActive={isChaoticAetherActive}
      showPhenomenonResolver={showPhenomenonResolver}
      isPending={isPending}
      onResolvePhenomenon={resolvePhenomenon}
    />
  );
  const actionButtons = (
    <GameActionButtons
      isTreacheryActive={isTreacheryActive}
      currentPlayer={currentPlayer}
      isHost={isHost}
      isPending={isPending}
      canResolveAbility={abilityResolver.canResolveAbility}
      onUnveil={confirmDialog.requestUnveil}
      onActivateAbility={abilityResolver.open}
      onForfeit={confirmDialog.requestForfeit}
      onEndGame={winnerSelection.open}
    />
  );
  const playerBoardProps = {
    players,
    currentUserId,
    isTreacheryActive,
    isEliminatedSpectator,
    canSeeRole,
    onAdjustLife: adjustLife,
    onViewCard: setInspectedPlayer,
    onRename: renameCurrentPlayer,
    onColorChange: updatePlayerColor,
  };

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
            {identityHeader}
            {planechaseStatus}

            {/* Always-visible plane card image (rotated 90° clockwise).
                Hidden while a phenomenon is waiting to resolve so the overlay
                is not stacked under a second copy of the same card. */}
            {isPlanechaseActive &&
              !isOwnDeckMode &&
              currentPlane?.image_uri &&
              !showPhenomenonResolver && (
                <SidebarPlaneImage
                  planeName={currentPlane.name}
                  imageUri={currentPlane.image_uri}
                  onPress={() => setShowPlaneDetail(true)}
                />
              )}

            <View style={{ flex: 1 }} />

            {actionButtons}
          </ScrollView>
        )}

        {/* ── Main content area ── */}
        <View style={isDesktop ? styles.mainContent : styles.mobileColumn}>
          {/* Mobile-only: identity card header and Planechase status */}
          {!isDesktop && identityHeader}
          {!isDesktop && planechaseStatus}

          {/* Ornate divider */}
          <View style={styles.ornateDividerRow}>
            <View style={styles.ornateLine} />
            <Text style={styles.ornateDiamond}>&#9670;</Text>
            <View style={styles.ornateLine} />
          </View>

          {/* Player list — desktop gets the Round Table board, mobile keeps
              the vertical roster it has always had. */}
          {isDesktop ? (
            <GameRoundTable
              {...playerBoardProps}
              activePlayerId={activePlayerId}
              onReorder={reorderSeats}
              onAdvanceTurn={advanceTurn}
            />
          ) : (
            <GamePlayerList {...playerBoardProps} />
          )}

          {errorMessage && <ErrorBanner message={errorMessage} />}

          {/* Spectator overlay for eliminated players */}
          {currentPlayer?.is_eliminated && (
            <SpectatorBar onLeave={() => router.replace('/(app)')} />
          )}

          {/* Mobile-only: action bar and buttons */}
          {!isDesktop && actionButtons}
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
      {inspectedCard && inspectedPlayer && canSeeRole(inspectedPlayer) && (
        <IdentityCardDetail
          card={inspectedCard}
          player={inspectedPlayer}
          visible={!!inspectedPlayer}
          onClose={() => setInspectedPlayer(null)}
        />
      )}

      {/* Traitor ability resolver (Metamorph / Puppet Master / Wearer of Masks) */}
      {currentPlayer && (
        <AbilityResolver
          gameId={gameId!}
          currentPlayer={currentPlayer}
          players={players}
          visible={abilityResolver.isVisible}
          onClose={abilityResolver.close}
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

      <WinnerSelectionModal
        visible={winnerSelection.isVisible}
        players={alivePlayers}
        selectedWinners={winnerSelection.selectedWinners}
        isPending={isPending}
        onToggleWinner={winnerSelection.toggleWinner}
        onConfirm={winnerSelection.confirm}
        onClose={winnerSelection.close}
      />

      <ConfirmDialog {...confirmDialog.dialogProps} />
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
});
