import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Player } from '@/models/types';
import { colors, spacing } from '@/constants/theme';

interface GameActionButtonsProps {
  isTreacheryActive: boolean;
  currentPlayer: Player | null;
  isHost: boolean;
  isPending: boolean;
  canResolveAbility: boolean;
  onUnveil: () => void;
  onActivateAbility: () => void;
  onForfeit: () => void;
  onEndGame: () => void;
}

/**
 * The local player's game actions: Unveil Identity / Activate Ability and
 * Forfeit in treachery modes, the host's End Game otherwise. Hidden once the
 * player is eliminated.
 */
export function GameActionButtons({
  isTreacheryActive,
  currentPlayer,
  isHost,
  isPending,
  canResolveAbility,
  onUnveil,
  onActivateAbility,
  onForfeit,
  onEndGame,
}: GameActionButtonsProps) {
  return (
    <>
      {isTreacheryActive && currentPlayer && !currentPlayer.is_eliminated && (
        <View style={styles.actionBar}>
          {!currentPlayer.is_unveiled && currentPlayer.role !== 'leader' && (
            <TouchableOpacity
              style={[styles.unveilButton, isPending && styles.buttonDisabled]}
              onPress={onUnveil}
              disabled={isPending}
              accessibilityLabel="Unveil identity"
              accessibilityRole="button"
              accessibilityHint="Reveals your role and card to all players"
            >
              <Text style={styles.unveilButtonText}>Unveil Identity</Text>
            </TouchableOpacity>
          )}
          {canResolveAbility && (
            <TouchableOpacity
              style={[styles.unveilButton, isPending && styles.buttonDisabled]}
              onPress={onActivateAbility}
              disabled={isPending}
              accessibilityLabel="Activate ability"
              accessibilityRole="button"
            >
              <Text style={styles.unveilButtonText}>Activate Ability</Text>
            </TouchableOpacity>
          )}
        </View>
      )}

      {isTreacheryActive && currentPlayer && !currentPlayer.is_eliminated && (
        <TouchableOpacity
          style={[styles.forfeitButton, isPending && { opacity: 0.5 }]}
          onPress={onForfeit}
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
          onPress={onEndGame}
          disabled={isPending}
          accessibilityLabel="End game"
          accessibilityRole="button"
          accessibilityHint="Ends the game for all players"
        >
          <Ionicons name="stop-circle" size={16} color={colors.error} />
          <Text style={styles.endGameText}>End Game</Text>
        </TouchableOpacity>
      )}
    </>
  );
}

const styles = StyleSheet.create({
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
});
