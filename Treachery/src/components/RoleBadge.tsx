import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Role } from '@/models/types';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors, fonts } from '@/constants/theme';

interface RoleBadgeProps {
  count: number;
  role: Role;
}

export function RoleBadge({ count, role }: RoleBadgeProps) {
  const roleColor = ROLE_COLORS[role];
  return (
    <View style={[styles.container, { borderColor: roleColor + '40' }]}>
      <Text style={[styles.count, { color: roleColor }]}>{count}</Text>
      <Text style={[styles.label, { color: roleColor + 'BB' }]}>{ROLE_DISPLAY_NAMES[role]}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    gap: 2,
    borderWidth: 1,
    borderRadius: 8,
    paddingVertical: 8,
    paddingHorizontal: 12,
    backgroundColor: colors.surfaceLight,
  },
  count: {
    fontSize: 24,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  label: {
    fontSize: 10,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
});
