import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, fonts } from '@/constants/theme';

interface GameUnavailableScreenProps {
  onReturnHome: () => void;
}

/**
 * Full-screen fallback for a game that disappeared mid-session. Rendered
 * in-app rather than via Alert.alert, which is a silent no-op on
 * react-native-web.
 */
export function GameUnavailableScreen({ onReturnHome }: GameUnavailableScreenProps) {
  return (
    <View style={styles.centerContainer}>
      <Ionicons name="wifi" size={48} color={colors.warning} />
      <Text style={styles.unavailableTitle}>Game Unavailable</Text>
      <Text style={styles.unavailableText}>This game is no longer available.</Text>
      <TouchableOpacity
        style={styles.primaryButton}
        onPress={onReturnHome}
        accessibilityLabel="Return to home"
        accessibilityRole="button"
      >
        <Text style={styles.buttonText}>Return to Home</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  centerContainer: {
    flex: 1,
    backgroundColor: colors.background,
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.lg,
    gap: 12,
  },
  primaryButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    minWidth: 200,
  },
  buttonText: {
    color: '#0d0b1a',
    fontSize: 16,
    fontWeight: '700',
  },
  unavailableTitle: {
    color: colors.text,
    fontSize: 20,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  unavailableText: {
    color: colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
  },
});
