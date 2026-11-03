import React from 'react';
import { Modal, View, Text, TouchableOpacity, ScrollView, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Player } from '@/models/types';
import { colors, spacing, fonts } from '@/constants/theme';

interface WinnerSelectionModalProps {
  visible: boolean;
  /** Players eligible to be picked as winners. */
  players: Player[];
  /** user_ids currently checked. */
  selectedWinners: Set<string>;
  isPending: boolean;
  onToggleWinner: (userId: string) => void;
  onConfirm: () => void;
  onClose: () => void;
}

/**
 * The host's End Game sheet for non-treachery modes: pick the winner(s) for
 * ELO tracking, or confirm with none selected to skip the ELO update.
 */
export function WinnerSelectionModal({
  visible,
  players,
  selectedWinners,
  isPending,
  onToggleWinner,
  onConfirm,
  onClose,
}: WinnerSelectionModalProps) {
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={styles.modalOverlay}>
        <View style={styles.modalContent}>
          <Text style={styles.modalTitle}>End Game</Text>
          <Text style={styles.modalSubtitle}>
            Select the winner(s) of this game for ELO tracking.
          </Text>

          <ScrollView style={styles.winnerList}>
            {players.map((player) => (
              <TouchableOpacity
                key={player.user_id}
                style={styles.winnerRow}
                onPress={() => onToggleWinner(player.user_id)}
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
            onPress={onConfirm}
            disabled={isPending}
            accessibilityLabel="End game"
            accessibilityRole="button"
          >
            <Text style={styles.modalEndButtonText}>End Game</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.modalCancelButton}
            onPress={onClose}
            accessibilityLabel="Cancel"
            accessibilityRole="button"
          >
            <Text style={styles.modalCancelText}>Cancel</Text>
          </TouchableOpacity>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  buttonDisabled: {
    opacity: 0.5,
  },
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
