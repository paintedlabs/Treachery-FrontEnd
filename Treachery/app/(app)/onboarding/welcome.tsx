import React from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  Linking,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '@/hooks/useAuth';
import { colors, spacing, fonts } from '@/constants/theme';

const ROLES = [
  { name: 'Leader', color: '#E4C96A', description: 'Eliminate all Assassins and Traitors to win.' },
  { name: 'Guardian', color: '#4C8CC9', description: 'Keep the Leader alive. Eliminate all Assassins and Traitors.' },
  { name: 'Assassin', color: '#C94C4C', description: 'Eliminate the Leader while at least one Assassin survives.' },
  { name: 'Traitor', color: '#9C4CC9', description: 'Be the last player standing.' },
];

export default function WelcomeScreen() {
  const router = useRouter();
  const { completeOnboarding } = useAuth();

  const handleComplete = () => {
    completeOnboarding();
    router.replace('/(app)');
  };

  return (
    <ScrollView
      style={styles.scroll}
      contentContainerStyle={styles.container}
    >
      <View style={styles.spacer} />

      <Text style={styles.title}>Welcome to Treachery</Text>
      <Text style={styles.subtitle}>A Game of Hidden Allegiance</Text>

      {/* Ornate divider */}
      <View style={styles.dividerRow}>
        <View style={styles.dividerLine} />
        <Text style={styles.dividerDiamond}>&#9670;</Text>
        <View style={styles.dividerLine} />
      </View>

      <Text style={styles.description}>
        Each player is secretly assigned a role. Use deception and strategy to achieve your
        team&apos;s goal.
      </Text>

      {/* Role cards 2x2 grid */}
      <View style={styles.grid}>
        {ROLES.map((role) => (
          <View key={role.name} style={[styles.roleCard, { borderColor: role.color + '4D' }]}>
            <View style={[styles.roleAccent, { backgroundColor: role.color }]} />
            <View style={styles.roleContent}>
              <Text style={[styles.roleName, { color: role.color }]}>{role.name}</Text>
              <Text style={styles.roleDescription}>{role.description}</Text>
            </View>
          </View>
        ))}
      </View>

      {/* Ornate divider */}
      <View style={styles.dividerRow}>
        <View style={styles.dividerLine} />
        <Text style={styles.dividerDiamond}>&#9670;</Text>
        <View style={styles.dividerLine} />
      </View>

      <TouchableOpacity
        onPress={() => Linking.openURL('https://mtgtreachery.net')}
        accessibilityRole="link"
      >
        <Text style={styles.rulesLink}>Read the full rules at mtgtreachery.net</Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={styles.primaryButton}
        onPress={handleComplete}
        accessibilityLabel="Let's Play"
        accessibilityRole="button"
      >
        <Text style={styles.buttonText}>Let&apos;s Play</Text>
      </TouchableOpacity>

      <View style={styles.spacer} />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: { flex: 1, backgroundColor: colors.background },
  container: {
    padding: spacing.lg,
    alignItems: 'center',
  },
  spacer: { height: 48 },
  title: {
    color: colors.primaryBright,
    fontSize: 28,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
    textAlign: 'center',
    letterSpacing: 1,
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: 14,
    fontFamily: fonts.serif,
    fontStyle: 'italic',
    textAlign: 'center',
    marginTop: 4,
    marginBottom: spacing.lg,
  },
  dividerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    width: '100%',
    marginVertical: spacing.md,
    paddingHorizontal: spacing.xl,
  },
  dividerLine: { flex: 1, height: 1, backgroundColor: colors.border },
  dividerDiamond: { color: colors.primary, fontSize: 10 },
  description: {
    color: colors.textSecondary,
    fontSize: 14,
    fontFamily: fonts.serif,
    textAlign: 'center',
    marginBottom: spacing.lg,
    paddingHorizontal: spacing.sm,
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    width: '100%',
    marginBottom: spacing.md,
  },
  roleCard: {
    width: '48%',
    flexGrow: 1,
    flexBasis: '45%',
    backgroundColor: colors.surface,
    borderRadius: 10,
    borderWidth: 1,
    overflow: 'hidden',
    flexDirection: 'row',
  },
  roleAccent: {
    width: 3,
  },
  roleContent: {
    flex: 1,
    padding: 12,
  },
  roleName: {
    fontSize: 14,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
    marginBottom: 4,
  },
  roleDescription: {
    color: colors.textSecondary,
    fontSize: 11,
    fontFamily: fonts.serif,
    lineHeight: 15,
  },
  rulesLink: {
    color: colors.primary,
    fontSize: 12,
    fontFamily: fonts.serif,
    fontStyle: 'italic',
    marginBottom: spacing.lg,
  },
  primaryButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    width: '100%',
  },
  buttonText: {
    color: '#0d0b1a',
    fontSize: 16,
    fontWeight: '700',
  },
});
