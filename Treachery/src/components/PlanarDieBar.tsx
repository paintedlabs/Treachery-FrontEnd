import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors, fonts } from '@/constants/theme';

interface PlanarDieBarProps {
  cost: number;
  isRolling: boolean;
  lastResult: string | null;
  lastRollerName: string | null;
  onRoll: () => void;
}

const DIE_RESULT_CONFIG: Record<string, { icon: keyof typeof Ionicons.glyphMap; label: string; color: string }> = {
  blank: { icon: 'remove', label: 'Blank', color: colors.textSecondary },
  chaos: { icon: 'flame', label: 'Chaos', color: colors.warning },
  planeswalk: { icon: 'planet', label: 'Planeswalk', color: colors.primary },
};

export function PlanarDieBar({ cost, isRolling, lastResult, lastRollerName, onRoll }: PlanarDieBarProps) {
  const resultConfig = lastResult ? DIE_RESULT_CONFIG[lastResult] : null;

  return (
    <View style={styles.container}>
      {/* Last result display */}
      {resultConfig && lastRollerName && (
        <View style={styles.resultRow}>
          <Ionicons name={resultConfig.icon} size={16} color={resultConfig.color} />
          <Text style={[styles.resultText, { color: resultConfig.color }]}>
            {lastRollerName} rolled: {resultConfig.label}
          </Text>
        </View>
      )}

      {/* Roll button with cost */}
      <View style={styles.rollRow}>
        <TouchableOpacity
          style={[styles.rollButton, isRolling && styles.rollButtonDisabled]}
          onPress={onRoll}
          disabled={isRolling}
          activeOpacity={0.7}
          accessibilityLabel={`Roll planar die, costs ${cost} mana`}
          accessibilityRole="button"
        >
          {isRolling ? (
            <ActivityIndicator size="small" color={colors.background} />
          ) : (
            <>
              <Ionicons name="dice" size={20} color={colors.background} />
              <Text style={styles.rollButtonText}>Roll Planar Die</Text>
            </>
          )}
        </TouchableOpacity>

        {/* Mana cost indicator */}
        <View style={styles.costContainer}>
          <View style={styles.costCircle}>
            <Text style={styles.costText}>{cost}</Text>
          </View>
          <Text style={styles.costLabel}>mana</Text>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderTopWidth: 1,
    borderTopColor: colors.divider,
    backgroundColor: colors.surface,
    padding: 12,
    gap: 8,
  },
  resultRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingBottom: 4,
  },
  resultText: {
    fontSize: 13,
    fontWeight: '500',
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
  rollRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  rollButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    backgroundColor: colors.primary,
    borderRadius: 8,
    paddingVertical: 12,
  },
  rollButtonDisabled: {
    opacity: 0.5,
  },
  rollButtonText: {
    color: colors.background,
    fontSize: 16,
    fontWeight: '700',
  },
  costContainer: {
    alignItems: 'center',
    gap: 2,
  },
  costCircle: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    justifyContent: 'center',
    alignItems: 'center',
  },
  costText: {
    color: colors.text,
    fontSize: 16,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  costLabel: {
    color: colors.textTertiary,
    fontSize: 9,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
});
