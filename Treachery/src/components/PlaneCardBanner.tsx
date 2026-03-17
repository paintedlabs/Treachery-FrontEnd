import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { PlaneCard } from '@/models/types';
import { colors, fonts } from '@/constants/theme';

interface PlaneCardBannerProps {
  planeCard: PlaneCard;
  secondaryPlaneCard?: PlaneCard;
  onPress: () => void;
}

export function PlaneCardBanner({ planeCard, secondaryPlaneCard, onPress }: PlaneCardBannerProps) {
  const accentColor = planeCard.is_phenomenon ? colors.warning : colors.primary;

  return (
    <TouchableOpacity
      style={[styles.container, { borderColor: accentColor + '40' }]}
      onPress={onPress}
      activeOpacity={0.7}
      accessibilityLabel={
        secondaryPlaneCard
          ? `Current planes: ${planeCard.name} and ${secondaryPlaneCard.name}. Tap for details.`
          : `Current plane: ${planeCard.name}. Tap for details.`
      }
      accessibilityRole="button"
    >
      <View style={[styles.topTrim, { backgroundColor: accentColor }]} />
      <View style={styles.content}>
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
        <Ionicons name="chevron-forward" size={14} color={colors.textTertiary} />
      </View>
    </TouchableOpacity>
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
});
