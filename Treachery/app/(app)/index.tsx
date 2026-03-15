import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '@/hooks/useAuth';
import { colors, spacing, fontSize } from '@/constants/theme';

export default function HomeScreen() {
  const router = useRouter();
  const { authState } = useAuth();

  if (authState !== 'authenticated') return null;

  return (
    <View style={styles.container}>
      <View style={styles.spacer} />

      <Text style={styles.title}>Treachery</Text>

      <TouchableOpacity
        style={styles.primaryButton}
        onPress={() => router.push('/(app)/create-game')}
      >
        <Text style={styles.primaryButtonText}>Create Game</Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={styles.secondaryButton}
        onPress={() => router.push('/(app)/join-game')}
      >
        <Text style={styles.secondaryButtonText}>Join Game</Text>
      </TouchableOpacity>

      <View style={styles.spacer} />

      {/* Bottom navigation */}
      <View style={styles.bottomNav}>
        <TouchableOpacity
          style={styles.navItem}
          onPress={() => router.push('/(app)/history')}
        >
          <Ionicons name="time" size={24} color={colors.textSecondary} />
          <Text style={styles.navLabel}>History</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.navItem}
          onPress={() => router.push('/(app)/friends')}
        >
          <Ionicons name="people" size={24} color={colors.textSecondary} />
          <Text style={styles.navLabel}>Friends</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.navItem}
          onPress={() => router.push('/(app)/profile')}
        >
          <Ionicons name="person-circle" size={24} color={colors.textSecondary} />
          <Text style={styles.navLabel}>Profile</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: spacing.lg,
    alignItems: 'center',
    gap: spacing.lg,
  },
  spacer: {
    flex: 1,
  },
  title: {
    color: colors.text,
    fontSize: fontSize.largeTitle,
    fontWeight: 'bold',
    marginBottom: spacing.xl,
  },
  primaryButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    paddingVertical: 14,
    paddingHorizontal: 48,
    minWidth: 200,
    alignItems: 'center',
  },
  primaryButtonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
  },
  secondaryButton: {
    borderRadius: 8,
    paddingVertical: 14,
    paddingHorizontal: 48,
    minWidth: 200,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.primary,
  },
  secondaryButtonText: {
    color: colors.primary,
    fontSize: 16,
    fontWeight: '600',
  },
  bottomNav: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 36,
    paddingBottom: spacing.lg,
  },
  navItem: {
    alignItems: 'center',
    gap: 4,
  },
  navLabel: {
    color: colors.textSecondary,
    fontSize: 12,
  },
});
