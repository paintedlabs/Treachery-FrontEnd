import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { PlaneCard } from '@/models/types';
import { colors, fonts } from '@/constants/theme';

const DIE_RESULT_CONFIG: Record<
  string,
  { icon: keyof typeof Ionicons.glyphMap; label: string; color: string }
> = {
  blank: { icon: 'remove', label: 'Blank', color: colors.textSecondary },
  chaos: { icon: 'flame', label: 'Chaos', color: colors.warning },
  planeswalk: { icon: 'planet', label: 'Planeswalk', color: colors.primary },
};

interface PlaneCardBannerProps {
  planeCard: PlaneCard;
  secondaryPlaneCard?: PlaneCard;
  onPress: () => void;
  // Die controls (optional — shown inline when provided)
  dieCost?: number;
  isRolling?: boolean;
  onRollDie?: () => void;
  lastDieResult?: string | null;
  lastRollerName?: string | null;
}

export function PlaneCardBanner({
  planeCard,
  secondaryPlaneCard,
  onPress,
  dieCost,
  isRolling,
  onRollDie,
  lastDieResult,
  lastRollerName,
}: PlaneCardBannerProps) {
  const accentColor = planeCard.is_phenomenon ? colors.warning : colors.primary;
  const resultConfig = lastDieResult ? DIE_RESULT_CONFIG[lastDieResult] : null;
  const showDie = onRollDie !== undefined;

  return (
    <View style={[styles.container, { borderColor: accentColor + '40' }]}>
      <View style={[styles.topTrim, { backgroundColor: accentColor }]} />
      <View style={styles.content}>
        {/* Tappable plane info */}
        <TouchableOpacity
          style={styles.planeInfo}
          onPress={onPress}
          activeOpacity={0.7}
          accessibilityLabel={
            secondaryPlaneCard
              ? `Current planes: ${planeCard.name} and ${secondaryPlaneCard.name}. Tap for details.`
              : `Current plane: ${planeCard.name}. Tap for details.`
          }
          accessibilityRole="button"
        >
          <View style={styles.iconContainer}>
            <Ionicons
              name={planeCard.is_phenomenon ? 'flash' : 'planet'}
              size={20}
              color={accentColor}
            />
          </View>
          <View style={styles.textContainer}>
            <Text style={styles.name} numberOfLines={1}>
              {planeCard.name}
            </Text>
            <Text style={[styles.typeLine, { color: accentColor }]} numberOfLines={1}>
              {planeCard.type_line}
            </Text>
            {secondaryPlaneCard && (
              <>
                <View style={styles.dualDivider}>
                  <View style={styles.dualDividerLine} />
                  <Text style={styles.dualDividerPlus}>+</Text>
                  <View style={styles.dualDividerLine} />
                </View>
                <Text style={styles.name} numberOfLines={1}>
                  {secondaryPlaneCard.name}
                </Text>
                <Text style={[styles.typeLine, { color: colors.primary }]} numberOfLines={1}>
                  {secondaryPlaneCard.type_line}
                </Text>
              </>
            )}
          </View>
          {!showDie && <Ionicons name="chevron-forward" size={14} color={colors.textTertiary} />}
        </TouchableOpacity>

        {/* Inline die controls */}
        {showDie && (
          <View style={styles.dieControls}>
            <View style={styles.costCircle}>
              <Text style={styles.costText}>{dieCost ?? 0}</Text>
            </View>
            <TouchableOpacity
              style={[styles.dieButton, isRolling && styles.dieButtonDisabled]}
              onPress={onRollDie}
              disabled={isRolling}
              activeOpacity={0.7}
              accessibilityLabel={`Roll planar die, costs ${dieCost ?? 0} mana`}
              accessibilityRole="button"
            >
              {isRolling ? (
                <ActivityIndicator size="small" color={colors.background} />
              ) : (
                <Ionicons name="dice" size={22} color={colors.background} />
              )}
            </TouchableOpacity>
          </View>
        )}
      </View>

      {/* Last roll result */}
      {resultConfig && lastRollerName && (
        <View style={styles.resultRow}>
          <Ionicons name={resultConfig.icon} size={14} color={resultConfig.color} />
          <Text style={[styles.resultText, { color: resultConfig.color }]}>
            {lastRollerName}: {resultConfig.label}
          </Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderTopWidth: 0,
    overflow: 'hidden',
  },
  topTrim: {
    height: 3,
  },
  content: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingRight: 12,
  },
  planeInfo: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
    gap: 10,
  },
  iconContainer: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    justifyContent: 'center',
    alignItems: 'center',
  },
  textContainer: {
    flex: 1,
    gap: 2,
  },
  name: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
  typeLine: {
    fontSize: 11,
    fontWeight: '500',
    letterSpacing: 0.5,
  },
  dualDivider: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginVertical: 4,
  },
  dualDividerLine: {
    flex: 1,
    height: 1,
    backgroundColor: colors.border,
  },
  dualDividerPlus: {
    color: colors.textTertiary,
    fontSize: 12,
    fontWeight: '600',
  },
  // Die controls
  dieControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  costCircle: {
    width: 30,
    height: 30,
    borderRadius: 15,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    justifyContent: 'center',
    alignItems: 'center',
  },
  costText: {
    color: colors.text,
    fontSize: 14,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  dieButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  dieButtonDisabled: {
    opacity: 0.5,
  },
  resultRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingBottom: 8,
    paddingHorizontal: 16,
  },
  resultText: {
    fontSize: 12,
    fontWeight: '500',
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
});
