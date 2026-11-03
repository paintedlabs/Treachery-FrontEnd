import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, fonts } from '@/constants/theme';

interface SpectatorBarProps {
  onLeave: () => void;
}

/** Bottom bar shown to an eliminated player who is still watching the game. */
export function SpectatorBar({ onLeave }: SpectatorBarProps) {
  return (
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
        onPress={onLeave}
        accessibilityLabel="Leave game and return home"
        accessibilityRole="button"
      >
        <Text style={styles.spectatorLeaveText}>Leave Game</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
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
});
