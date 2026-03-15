import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Player, Role } from '@/models/types';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors } from '@/constants/theme';

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
    <View style={styles.container}>
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
          <Text style={styles.lifeText}>{player.life_total}</Text>
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
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.divider,
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
    backgroundColor: 'rgba(74, 144, 217, 0.2)',
    paddingHorizontal: 6,
    paddingVertical: 1,
    borderRadius: 10,
  },
  youText: {
    color: colors.primary,
    fontSize: 10,
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
  },
  unveiledText: {
    fontSize: 10,
    color: colors.textSecondary,
  },
  hiddenText: {
    fontSize: 12,
    color: colors.textSecondary,
  },
  lifeControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  lifeText: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '600',
    minWidth: 36,
    textAlign: 'center',
  },
  eliminatedText: {
    color: colors.error,
    fontSize: 12,
  },
});
