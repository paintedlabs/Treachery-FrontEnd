import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Linking,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '@/hooks/useAuth';
import { ErrorBanner } from '@/components/ErrorBanner';
import { colors, spacing, fonts } from '@/constants/theme';

export default function LoginScreen() {
  const router = useRouter();
  const { signIn, signInAsGuest, errorMessage, clearError } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isGuestLoading, setIsGuestLoading] = useState(false);

  const handleSignIn = async () => {
    if (!email.trim() || !password.trim()) return;
    clearError();
    setIsLoading(true);
    await signIn(email.trim(), password.trim());
    setIsLoading(false);
  };

  const handlePlayAsGuest = async () => {
    clearError();
    setIsGuestLoading(true);
    await signInAsGuest();
    setIsGuestLoading(false);
  };

  const busy = isLoading || isGuestLoading;

  return (
    <View style={styles.container}>
      <View style={styles.spacer} />

      <Text style={styles.title}>Treachery</Text>
      <Text style={styles.subtitle}>A Game of Hidden Allegiance</Text>

      {/* Ornate divider */}
      <View style={styles.ornateDivider}>
        <View style={styles.ornateLine} />
        <Text style={styles.ornateDiamond}>&#9670;</Text>
        <View style={styles.ornateLine} />
      </View>

      {errorMessage && <ErrorBanner message={errorMessage} />}

      <TextInput
        style={styles.input}
        placeholder="Email"
        placeholderTextColor={colors.textTertiary}
        value={email}
        onChangeText={setEmail}
        autoCapitalize="none"
        keyboardType="email-address"
        textContentType="emailAddress"
        editable={!busy}
        accessibilityLabel="Email"
      />

      <TextInput
        style={styles.input}
        placeholder="Password"
        placeholderTextColor={colors.textTertiary}
        value={password}
        onChangeText={setPassword}
        secureTextEntry
        textContentType="password"
        editable={!busy}
        accessibilityLabel="Password"
      />

      <TouchableOpacity
        style={[styles.primaryButton, busy && styles.buttonDisabled]}
        onPress={handleSignIn}
        disabled={busy}
        accessibilityLabel="Sign in"
        accessibilityRole="button"
      >
        {isLoading ? (
          <View style={styles.buttonRow}>
            <ActivityIndicator size="small" color="#0d0b1a" />
            <Text style={styles.buttonText}>Signing In...</Text>
          </View>
        ) : (
          <Text style={styles.buttonText}>Sign In</Text>
        )}
      </TouchableOpacity>

      <View style={styles.linkRow}>
        <TouchableOpacity onPress={() => router.push('/(auth)/signup')} disabled={busy}>
          <Text style={styles.linkText}>Create Account</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={() => router.push('/(auth)/forgot-password')} disabled={busy}>
          <Text style={styles.linkText}>Forgot Password?</Text>
        </TouchableOpacity>
      </View>

      <TouchableOpacity
        style={[styles.phoneButton, busy && styles.buttonDisabled]}
        onPress={() => router.push('/(auth)/phone-login')}
        disabled={busy}
        accessibilityLabel="Sign in with phone number"
        accessibilityRole="button"
      >
        <Text style={styles.phoneButtonText}>Sign In with Phone</Text>
      </TouchableOpacity>

      {/* Divider */}
      <View style={styles.separatorRow}>
        <View style={styles.separatorLine} />
        <Text style={styles.separatorText}>or</Text>
        <View style={styles.separatorLine} />
      </View>

      <TouchableOpacity
        style={[styles.guestButton, busy && styles.buttonDisabled]}
        onPress={handlePlayAsGuest}
        disabled={busy}
        accessibilityLabel="Play as Guest"
        accessibilityRole="button"
      >
        {isGuestLoading ? (
          <View style={styles.buttonRow}>
            <ActivityIndicator size="small" color={colors.primary} />
            <Text style={styles.guestButtonText}>Joining...</Text>
          </View>
        ) : (
          <Text style={styles.guestButtonText}>Play as Guest</Text>
        )}
      </TouchableOpacity>

      <View style={styles.spacer} />

      <TouchableOpacity
        style={styles.footerLink}
        onPress={() => Linking.openURL('https://testflight.apple.com/join/Ws9HWGA7')}
        accessibilityLabel="Download the iOS app on TestFlight"
        accessibilityRole="link"
      >
        <Text style={styles.footerLinkText}>Download the iOS App (TestFlight)</Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={styles.footerLink}
        onPress={() => Linking.openURL('https://mtgtreachery.net')}
        accessibilityLabel="Learn the rules at MTGTreachery.net"
        accessibilityRole="link"
      >
        <Text style={styles.footerLinkText}>Learn the rules at MTGTreachery.net</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: spacing.lg,
  },
  spacer: {
    flex: 1,
  },
  title: {
    color: colors.primaryBright,
    fontSize: 42,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
    textAlign: 'center',
    letterSpacing: 2,
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
  ornateDivider: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: spacing.xl,
    paddingHorizontal: 32,
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
  input: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: 14,
    color: colors.text,
    fontSize: 16,
    marginBottom: 12,
  },
  primaryButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    marginTop: 4,
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  buttonText: {
    color: '#0d0b1a',
    fontSize: 16,
    fontWeight: '700',
  },
  linkRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 12,
  },
  linkText: {
    color: colors.primary,
    fontSize: 14,
  },
  separatorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginVertical: spacing.lg,
  },
  separatorLine: {
    flex: 1,
    height: 1,
    backgroundColor: colors.border,
  },
  separatorText: {
    color: colors.textTertiary,
    fontSize: 13,
  },
  phoneButton: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    marginTop: spacing.md,
  },
  phoneButtonText: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
  guestButton: {
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
  },
  guestButtonText: {
    color: colors.primary,
    fontSize: 16,
    fontWeight: '600',
  },
  footerLink: {
    alignItems: 'center',
    paddingBottom: spacing.sm,
  },
  footerLinkText: {
    color: colors.textTertiary,
    fontSize: 12,
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
});
