import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { colors, fonts } from '@/constants/theme';

interface StatBoxProps {
  value: string;
  label: string;
  color: string;
}

export function StatBox({ value, label, color }: StatBoxProps) {
  return (
    <View style={styles.container}>
      <View style={styles.valueBox}>
        <Text style={[styles.value, { color }]}>{value}</Text>
      </View>
      <Text style={styles.label}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    gap: 4,
  },
  valueBox: {
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 6,
    paddingVertical: 8,
    paddingHorizontal: 12,
    minWidth: 48,
    alignItems: 'center',
  },
  value: {
    fontSize: 22,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  label: {
    fontSize: 10,
    color: colors.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
});
