import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '@/hooks/useAuth';
import { colors, spacing, fontSize, fonts } from '@/constants/theme';

export default function HomeScreen() {
  const router = useRouter();
  const { authState } = useAuth();

  if (authState !== 'authenticated') return null;

  return (
    <View style={styles.container}>
      <View style={styles.spacer} />

      {/* Title treatment */}
      <View style={styles.titleSection}>
        <Text style={styles.title}>Treachery</Text>
        <Text style={styles.subtitle}>A Game of Hidden Allegiance</Text>

        {/* Ornate divider */}
        <View style={styles.ornateDivider}>
          <View style={styles.ornateLine} />
          <Text style={styles.ornateDiamond}>&#9670;</Text>
          <View style={styles.ornateLine} />
        </View>
      </View>

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
  titleSection: {
    alignItems: 'center',
    marginBottom: spacing.lg,
  },
  title: {
    color: colors.primaryBright,
    fontSize: 48,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
    letterSpacing: 3,
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: 14,
    fontFamily: fonts.serif,
    fontStyle: 'italic',
    marginTop: 4,
    marginBottom: spacing.lg,
  },
  ornateDivider: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    width: 200,
  },
  ornateLine: {
    flex: 1,
    height: 1,
    backgroundColor: colors.border,
  },
  ornateDiamond: {
    color: colors.primary,
    fontSize: 10,
  },
  primaryButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    paddingVertical: 14,
    paddingHorizontal: 48,
    minWidth: 220,
    alignItems: 'center',
  },
  primaryButtonText: {
    color: '#0d0b1a',
    fontSize: 16,
    fontWeight: '700',
  },
  secondaryButton: {
    borderRadius: 8,
    paddingVertical: 14,
    paddingHorizontal: 48,
    minWidth: 220,
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
