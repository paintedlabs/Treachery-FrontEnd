import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, fonts } from '@/constants/theme';

export function ChaoticAetherBanner() {
  return (
    <View style={styles.container}>
      <Ionicons name="flash" size={14} color={colors.warning} />
      <Text style={styles.text}>
        <Text style={styles.bold}>Chaotic Aether Active</Text>
        {' \u2014 Blanks become Chaos'}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: 'rgba(212, 148, 60, 0.12)',
    borderWidth: 1,
    borderColor: 'rgba(212, 148, 60, 0.3)',
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
  },
  text: {
    color: colors.warning,
    fontSize: 12,
    flex: 1,
  },
  bold: {
    fontWeight: '700',
    color: colors.primary,
  },
});
