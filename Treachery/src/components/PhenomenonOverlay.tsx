import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ActivityIndicator } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { PlaneCard } from '@/models/types';
import { colors, spacing, fonts } from '@/constants/theme';

interface PhenomenonOverlayProps {
  plane: PlaneCard;
  isPending?: boolean;
  onResolve: () => void;
}

/** Shown when the current plane is a phenomenon, with a Resolve action. */
export function PhenomenonOverlay({ plane, isPending, onResolve }: PhenomenonOverlayProps) {
  return (
    <View style={styles.container} accessibilityRole="summary">
      <View style={styles.titleRow}>
        <Ionicons name="sparkles" size={20} color={colors.primary} />
        <Text style={styles.badge}>PHENOMENON</Text>
        <Ionicons name="sparkles" size={20} color={colors.primary} />
      </View>
      <Text style={styles.name}>{plane.name}</Text>
      {!!plane.oracle_text && <Text style={styles.oracle}>{plane.oracle_text}</Text>}
      <TouchableOpacity
        style={[styles.button, isPending && styles.buttonDisabled]}
        onPress={onResolve}
        disabled={isPending}
        accessibilityLabel="Resolve phenomenon"
        accessibilityRole="button"
      >
        {isPending ? (
          <ActivityIndicator color={colors.background} />
        ) : (
          <Text style={styles.buttonText}>Resolve Phenomenon</Text>
        )}
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.primary,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    marginBottom: spacing.sm,
    gap: spacing.sm,
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.sm,
  },
  badge: {
    color: colors.primary,
    fontFamily: fonts.serif,
    fontWeight: '700',
    letterSpacing: 1.5,
  },
  name: {
    color: colors.text,
    fontFamily: fonts.serif,
    fontSize: 18,
    fontWeight: '600',
    textAlign: 'center',
  },
  oracle: {
    color: colors.textSecondary,
    textAlign: 'center',
    lineHeight: 20,
  },
  button: {
    alignSelf: 'center',
    backgroundColor: colors.primary,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    borderRadius: 4,
    minWidth: 200,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: colors.background,
    fontWeight: '600',
  },
});
