import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Role } from '@/models/types';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors } from '@/constants/theme';

interface RoleBadgeProps {
  count: number;
  role: Role;
}

export function RoleBadge({ count, role }: RoleBadgeProps) {
  return (
    <View style={styles.container}>
      <Text style={[styles.count, { color: ROLE_COLORS[role] }]}>{count}</Text>
      <Text style={styles.label}>{ROLE_DISPLAY_NAMES[role]}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    gap: 2,
  },
  count: {
    fontSize: 24,
    fontWeight: 'bold',
  },
  label: {
    fontSize: 10,
    color: colors.textSecondary,
  },
});
