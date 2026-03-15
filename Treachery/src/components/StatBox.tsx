import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { colors } from '@/constants/theme';

interface StatBoxProps {
  value: string;
  label: string;
  color: string;
}

export function StatBox({ value, label, color }: StatBoxProps) {
  return (
    <View style={styles.container}>
      <Text style={[styles.value, { color }]}>{value}</Text>
      <Text style={styles.label}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    gap: 2,
  },
  value: {
    fontSize: 24,
    fontWeight: 'bold',
  },
  label: {
    fontSize: 10,
    color: colors.textSecondary,
  },
});
