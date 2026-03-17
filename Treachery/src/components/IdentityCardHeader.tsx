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
  const isAlwaysVisible = player.is_unveiled || player.role === 'leader';

  if (isAlwaysVisible) {
    return (
      <TouchableOpacity
        style={[styles.container, { borderColor: roleColor + '60' }]}
        onPress={onPress}
        activeOpacity={0.7}
        accessibilityLabel={`Your identity card: ${card.name}, ${player.role ? ROLE_DISPLAY_NAMES[player.role] : 'Unknown'} role, ${player.life_total} life`}
        accessibilityRole="button"
        accessibilityHint="Opens full identity card view"
      >
        <View style={[styles.topTrim, { backgroundColor: roleColor }]} />
        <RevealedContent card={card} player={player} roleColor={roleColor} />
      </TouchableOpacity>
    );
  }

  return (
    <TouchableOpacity
      style={[styles.container, { borderColor: colors.border }]}
      onPress={onPress}
      activeOpacity={0.7}
      accessibilityLabel="Your secret identity. Tap to peek."
      accessibilityRole="button"
      accessibilityHint="Opens full identity card view"
    >
      <View style={[styles.topTrim, { backgroundColor: colors.primary }]} />
      <ConcealedContent player={player} />
    </TouchableOpacity>
  );
}

// ── Concealed (tap to open sheet) ─────────────────────────────────────

function ConcealedContent({
  player,
}: {
  player: Player;
}) {
  return (
    <>
      <View style={styles.topRow}>
        <Ionicons
          name="eye-off"
          size={22}
          color={colors.primary}
        />
        <View style={styles.lifeBox}>
          <Text style={styles.lifeText}>{player.life_total}</Text>
        </View>
      </View>

      <Text style={styles.tapHintConcealed}>Tap to peek at your identity</Text>
    </>
  );
}

// ── Revealed content (unveiled or leader) ─────────────────────────────

function RevealedContent({
  card,
  player,
  roleColor,
}: {
  card: IdentityCard;
  player: Player;
  roleColor: string;
}) {
  return (
    <>
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

      <View style={styles.nameRow}>
        <Text style={styles.cardName}>{card.name}</Text>
        <Ionicons name="chevron-forward" size={12} color={colors.textTertiary} />
      </View>

      <View style={styles.ornateDivider}>
        <View style={styles.ornateLine} />
        <Text style={styles.ornateDiamond}>&#9670;</Text>
        <View style={styles.ornateLine} />
      </View>

      <Text style={styles.abilityText} numberOfLines={3}>
        {card.ability_text}
      </Text>

      <View style={styles.bottomRow}>
        {player.is_unveiled ? (
          <View style={[styles.unveiledBadge, { backgroundColor: roleColor }]}>
            <Text style={styles.unveiledText}>UNVEILED</Text>
          </View>
        ) : player.role === 'leader' ? (
          <View style={styles.leaderBadge}>
            <Text style={styles.leaderBadgeText}>LEADER — ALWAYS VISIBLE</Text>
          </View>
        ) : null}
        <Text style={styles.tapHint}>Tap for details</Text>
      </View>
    </>
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
    alignSelf: 'flex-start',
    marginTop: 4,
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
  leaderBadge: {
    backgroundColor: 'rgba(201, 168, 76, 0.15)',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
  },
  leaderBadgeText: {
    color: colors.primary,
    fontSize: 10,
    fontWeight: 'bold',
    letterSpacing: 0.5,
  },
  tapHint: {
    color: colors.textTertiary,
    fontSize: 10,
    fontStyle: 'italic',
  },
  // Concealed-specific styles
  tapHintConcealed: {
    color: colors.textSecondary,
    fontSize: 14,
  },
});
