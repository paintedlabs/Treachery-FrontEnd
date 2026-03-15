import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Player, IdentityCard } from '@/models/types';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors } from '@/constants/theme';

interface IdentityCardHeaderProps {
  card: IdentityCard;
  player: Player;
  onPress: () => void;
}

export function IdentityCardHeader({ card, player, onPress }: IdentityCardHeaderProps) {
  const roleColor = player.role ? ROLE_COLORS[player.role] : colors.textSecondary;

  return (
    <TouchableOpacity
      style={styles.container}
      onPress={onPress}
      activeOpacity={0.7}
      accessibilityLabel={`Your identity card: ${card.name}, ${player.role ? ROLE_DISPLAY_NAMES[player.role] : 'Unknown'} role, ${player.life_total} life`}
      accessibilityHint="Opens full identity card view"
    >
      {/* Role and life */}
      <View style={styles.topRow}>
        <View style={styles.roleRow}>
          <View style={[styles.roleDot, { backgroundColor: roleColor }]} />
          <Text style={[styles.roleText, { color: roleColor }]}>
            {player.role ? ROLE_DISPLAY_NAMES[player.role] : 'Unknown'}
          </Text>
        </View>
        <Text style={styles.lifeText}>Life: {player.life_total}</Text>
      </View>

      {/* Card name */}
      <View style={styles.nameRow}>
        <Text style={styles.cardName}>{card.name}</Text>
        <Ionicons name="chevron-forward" size={12} color={colors.textTertiary} />
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
    backgroundColor: colors.surface,
    gap: 8,
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
  },
  lifeText: {
    color: colors.text,
    fontSize: 22,
    fontWeight: 'bold',
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
  },
  abilityText: {
    color: colors.textSecondary,
    fontSize: 12,
  },
  bottomRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  unveilBadge: {
    backgroundColor: 'rgba(255,255,255,0.1)',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
  },
  unveilText: {
    color: colors.textSecondary,
    fontSize: 10,
  },
  unveiledBadge: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
  },
  unveiledText: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: 'bold',
  },
  tapHint: {
    color: colors.textTertiary,
    fontSize: 10,
  },
});
