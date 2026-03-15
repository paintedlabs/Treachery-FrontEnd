import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Player, Role } from '@/models/types';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors, fonts } from '@/constants/theme';

interface PlayerRowProps {
  player: Player;
  isCurrentUser: boolean;
  canSeeRole: boolean;
  isUnveiledOrLeader: boolean;
  onAdjustLife: (amount: number) => void;
  onViewCard?: () => void;
}

export function PlayerRow({
  player,
  isCurrentUser,
  canSeeRole,
  isUnveiledOrLeader,
  onAdjustLife,
  onViewCard,
}: PlayerRowProps) {
  const roleColor = player.role ? ROLE_COLORS[player.role] : colors.textSecondary;

  return (
    <View style={[styles.container, isCurrentUser && styles.containerHighlight]}>
      {/* Left role accent bar */}
      {canSeeRole && player.role && (
        <View style={[styles.accentBar, { backgroundColor: roleColor }]} />
      )}

      <View style={styles.info}>
        <View style={styles.nameRow}>
          <Text
            style={[
              styles.name,
              isCurrentUser && styles.nameBold,
              player.is_eliminated && styles.nameEliminated,
            ]}
          >
            {player.display_name}
          </Text>
          {isCurrentUser && (
            <View style={styles.youBadge}>
              <Text style={styles.youText}>You</Text>
            </View>
          )}
          {player.is_eliminated && (
            <Ionicons name="close-circle" size={14} color={colors.error} />
          )}
        </View>

        {canSeeRole && player.role ? (
          <TouchableOpacity
            onPress={isUnveiledOrLeader && !isCurrentUser ? onViewCard : undefined}
            style={styles.roleRow}
            disabled={!isUnveiledOrLeader || isCurrentUser}
          >
            <View style={[styles.roleDot, { backgroundColor: roleColor }]} />
            <Text style={[styles.roleText, { color: roleColor }]}>
              {ROLE_DISPLAY_NAMES[player.role]}
            </Text>
            {player.is_unveiled && player.role !== 'leader' && !isCurrentUser && (
              <Text style={styles.unveiledText}>(Unveiled)</Text>
            )}
            {isUnveiledOrLeader && !isCurrentUser && (
              <Ionicons name="information-circle-outline" size={12} color={roleColor} />
            )}
          </TouchableOpacity>
        ) : (
          <Text style={styles.hiddenText}>Role Hidden</Text>
        )}
      </View>

      {!player.is_eliminated ? (
        <View style={styles.lifeControls}>
          <TouchableOpacity onPress={() => onAdjustLife(-1)}>
            <Ionicons name="remove-circle" size={28} color={colors.error} />
          </TouchableOpacity>
          <View style={styles.lifeBox}>
            <Text style={styles.lifeText}>{player.life_total}</Text>
          </View>
          <TouchableOpacity onPress={() => onAdjustLife(1)}>
            <Ionicons name="add-circle" size={28} color={colors.success} />
          </TouchableOpacity>
        </View>
      ) : (
        <Text style={styles.eliminatedText}>Eliminated</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
    backgroundColor: colors.surface,
  },
  containerHighlight: {
    backgroundColor: colors.surfaceLight,
  },
  accentBar: {
    width: 3,
    alignSelf: 'stretch',
    borderRadius: 2,
    marginRight: 10,
  },
  info: {
    flex: 1,
    gap: 2,
  },
  nameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  name: {
    color: colors.text,
    fontSize: 16,
  },
  nameBold: {
    fontWeight: 'bold',
  },
  nameEliminated: {
    textDecorationLine: 'line-through',
    color: colors.textSecondary,
  },
  youBadge: {
    backgroundColor: 'rgba(201, 168, 76, 0.2)',
    borderWidth: 1,
    borderColor: 'rgba(201, 168, 76, 0.3)',
    paddingHorizontal: 6,
    paddingVertical: 1,
    borderRadius: 10,
  },
  youText: {
    color: colors.primary,
    fontSize: 10,
    fontWeight: '600',
  },
  roleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  roleDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  roleText: {
    fontSize: 12,
    fontWeight: '500',
  },
  unveiledText: {
    fontSize: 10,
    color: colors.textSecondary,
    fontStyle: 'italic',
  },
  hiddenText: {
    fontSize: 12,
    color: colors.textTertiary,
    fontStyle: 'italic',
  },
  lifeControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  lifeBox: {
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 6,
    paddingVertical: 4,
    paddingHorizontal: 8,
    minWidth: 44,
    alignItems: 'center',
  },
  lifeText: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '700',
    fontFamily: fonts.serif,
    textAlign: 'center',
  },
  eliminatedText: {
    color: colors.error,
    fontSize: 12,
    fontStyle: 'italic',
  },
});
