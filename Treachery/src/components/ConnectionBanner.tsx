import React from 'react';
import { View, Text, StyleSheet, ActivityIndicator } from 'react-native';
import { colors, spacing } from '@/constants/theme';
import { useConnectionStatus } from '@/hooks/useConnectionStatus';

export function ConnectionBanner() {
  const { isOffline } = useConnectionStatus();

  if (!isOffline) return null;

  return (
    <View
      style={styles.banner}
      accessibilityRole="alert"
      accessibilityLabel="Reconnecting to server"
    >
      <ActivityIndicator size="small" color={colors.warning} />
      <Text style={styles.text}>Reconnecting...</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  banner: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    backgroundColor: 'rgba(212, 148, 60, 0.15)',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(212, 148, 60, 0.3)',
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.lg,
  },
  text: {
    color: colors.warning,
    fontSize: 13,
    fontWeight: '600',
  },
});
