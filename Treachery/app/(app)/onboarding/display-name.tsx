import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '@/hooks/useAuth';
import { ErrorBanner } from '@/components/ErrorBanner';
import { colors, spacing, fonts } from '@/constants/theme';

export default function DisplayNameScreen() {
  const router = useRouter();
  const { user, updateDisplayName } = useAuth();
  const [displayName, setDisplayName] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const [validationError, setValidationError] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    if (user.email) {
      const prefix = user.email.split('@')[0] || '';
      setDisplayName(prefix.charAt(0).toUpperCase() + prefix.slice(1));
    } else if (user.isAnonymous) {
      setDisplayName('Guest');
    } else {
      setDisplayName('Player');
    }
  }, [user]);

  const handleContinue = async () => {
    const trimmed = displayName.trim();
    if (!trimmed) {
      setValidationError('Please enter a display name.');
      return;
    }
    setValidationError(null);
    setIsSaving(true);
    await updateDisplayName(trimmed);
    setIsSaving(false);
    router.replace('/(app)/onboarding/welcome');
  };

  const handleSkip = () => {
    router.replace('/(app)/onboarding/welcome');
  };

  return (
    <View style={styles.container}>
      <View style={styles.spacer} />

      <Text style={styles.title}>Choose Your Name</Text>
      <Text style={styles.subtitle}>This is how other players will see you</Text>

      {/* Ornate divider */}
      <View style={styles.dividerRow}>
        <View style={styles.dividerLine} />
        <Text style={styles.dividerDiamond}>&#9670;</Text>
        <View style={styles.dividerLine} />
      </View>

      <TextInput
        style={styles.input}
        value={displayName}
        onChangeText={(text) => {
          setDisplayName(text);
          setValidationError(null);
        }}
        placeholder="Display Name"
        placeholderTextColor={colors.textTertiary}
        autoCapitalize="words"
        textContentType="name"
        maxLength={30}
        editable={!isSaving}
        accessibilityLabel="Display name"
      />

      {validationError && <ErrorBanner message={validationError} />}

      <TouchableOpacity
        style={[styles.primaryButton, isSaving && styles.buttonDisabled]}
        onPress={handleContinue}
        disabled={isSaving}
        accessibilityLabel="Continue"
        accessibilityRole="button"
      >
        {isSaving ? (
          <View style={styles.buttonRow}>
            <ActivityIndicator size="small" color="#0d0b1a" />
            <Text style={styles.buttonText}>Saving...</Text>
          </View>
        ) : (
          <Text style={styles.buttonText}>Continue</Text>
        )}
      </TouchableOpacity>

      <TouchableOpacity
        style={styles.skipButton}
        onPress={handleSkip}
        disabled={isSaving}
        accessibilityLabel="Skip"
        accessibilityRole="button"
      >
        <Text style={styles.skipText}>Skip</Text>
      </TouchableOpacity>

      <View style={styles.spacer} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: spacing.lg,
  },
  spacer: { flex: 1 },
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
    marginBottom: spacing.xl,
    paddingHorizontal: spacing.xl,
  },
  dividerLine: { flex: 1, height: 1, backgroundColor: colors.border },
  dividerDiamond: { color: colors.primary, fontSize: 10 },
  input: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: 14,
    color: colors.text,
    fontSize: 16,
    marginBottom: 12,
    textAlign: 'center',
  },
  primaryButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    marginTop: 4,
  },
  buttonDisabled: { opacity: 0.5 },
  buttonRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  buttonText: { color: '#0d0b1a', fontSize: 16, fontWeight: '700' },
  skipButton: { alignItems: 'center', marginTop: spacing.lg },
  skipText: { color: colors.primary, fontSize: 14, fontFamily: fonts.serif },
});
