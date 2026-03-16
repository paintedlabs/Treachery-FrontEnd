import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Player, IdentityCard } from '@/models/types';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors, fonts } from '@/constants/theme';

interface IdentityCardHeaderProps {
  card: IdentityCard;
  player: Player;
  onPress: () => void;
}

export function IdentityCardHeader({ card, player, onPress }: IdentityCardHeaderProps) {
  const roleColor = player.role ? ROLE_COLORS[player.role] : colors.textSecondary;

  return (
    <TouchableOpacity
      style={[styles.container, { borderColor: roleColor + '60' }]}
      onPress={onPress}
      activeOpacity={0.7}
      accessibilityLabel={`Your identity card: ${card.name}, ${player.role ? ROLE_DISPLAY_NAMES[player.role] : 'Unknown'} role, ${player.life_total} life`}
      accessibilityRole="button"
      accessibilityHint="Opens full identity card view"
    >
      {/* Top gold trim */}
      <View style={[styles.topTrim, { backgroundColor: roleColor }]} />

      {/* Role and life */}
      <View style={styles.topRow}>
        <View style={styles.roleRow}>
          <View style={[styles.roleDot, { backgroundColor: roleColor }]} />
          <Text style={[styles.roleText, { color: roleColor }]}>
            {player.role ? ROLE_DISPLAY_NAMES[player.role] : 'Unknown'}
          </Text>
        </View>
        <View style={styles.lifeBox}>
          <Text style={styles.lifeText}>{player.life_total}</Text>
        </View>
      </View>

      {/* Card name */}
      <View style={styles.nameRow}>
        <Text style={styles.cardName}>{card.name}</Text>
        <Ionicons name="chevron-forward" size={12} color={colors.textTertiary} />
      </View>

      {/* Ornate divider */}
      <View style={styles.ornateDivider}>
        <View style={styles.ornateLine} />
        <Text style={styles.ornateDiamond}>&#9670;</Text>
        <View style={styles.ornateLine} />
      </View>

      {/* Ability text */}
      <Text style={styles.abilityText} numberOfLines={3}>
        {card.ability_text}
      </Text>

      {/* Unveil status */}
      <View style={styles.bottomRow}>
        {!player.is_unveiled ? (
          <View style={styles.unveilBadge}>
            <Text style={styles.unveilText}>Unveil: {card.unveil_cost}</Text>
          </View>
        ) : (
          <View style={[styles.unveiledBadge, { backgroundColor: roleColor }]}>
            <Text style={styles.unveiledText}>UNVEILED</Text>
          </View>
        )}
        <Text style={styles.tapHint}>Tap for details</Text>
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 16,
    paddingTop: 0,
    backgroundColor: colors.surface,
    gap: 8,
    borderWidth: 1,
    borderTopWidth: 0,
    overflow: 'hidden',
  },
  topTrim: {
    height: 3,
    marginHorizontal: -16,
    marginBottom: 12,
  },
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  roleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  roleDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
  },
  roleText: {
    fontSize: 16,
    fontWeight: '600',
    fontFamily: fonts.serif,
  },
  lifeBox: {
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 6,
    paddingVertical: 4,
    paddingHorizontal: 12,
  },
  lifeText: {
    color: colors.text,
    fontSize: 24,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  nameRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  cardName: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '600',
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
  ornateDivider: {
    flexDirection: 'row',
    alignItems: 'center',
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
  abilityText: {
    color: colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  bottomRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  unveilBadge: {
    backgroundColor: 'rgba(201, 168, 76, 0.12)',
    borderWidth: 1,
    borderColor: 'rgba(201, 168, 76, 0.25)',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
  },
  unveilText: {
    color: colors.primary,
    fontSize: 10,
    fontWeight: '500',
  },
  unveiledBadge: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
  },
  unveiledText: {
    color: '#0d0b1a',
    fontSize: 10,
    fontWeight: 'bold',
    letterSpacing: 1,
  },
  tapHint: {
    color: colors.textTertiary,
    fontSize: 10,
    fontStyle: 'italic',
  },
});
