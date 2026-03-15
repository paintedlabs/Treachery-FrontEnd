import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '@/hooks/useAuth';
import { ErrorBanner } from '@/components/ErrorBanner';
import { colors, spacing, fontSize, fonts } from '@/constants/theme';

export default function LoginScreen() {
  const router = useRouter();
  const { signIn, resetPassword, errorMessage, clearError } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isSigningIn, setIsSigningIn] = useState(false);

  const handleSignIn = async () => {
    if (!email || !password) return;
    setIsSigningIn(true);
    await signIn(email, password);
    setIsSigningIn(false);
  };

  const handleResetPassword = async () => {
    if (!email) return;
    await resetPassword(email);
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <View style={styles.spacer} />

      <Text style={styles.title}>Treachery</Text>
      <Text style={styles.subtitle}>A Game of Hidden Allegiance</Text>

      {/* Ornate divider */}
      <View style={styles.ornateDivider}>
        <View style={styles.ornateLine} />
        <Text style={styles.ornateDiamond}>&#9670;</Text>
        <View style={styles.ornateLine} />
      </View>

      <View style={styles.form}>
        <TextInput
          style={styles.input}
          placeholder="Email"
          placeholderTextColor={colors.textTertiary}
          value={email}
          onChangeText={(text) => {
            setEmail(text);
            clearError();
          }}
          keyboardType="email-address"
          autoCapitalize="none"
          autoCorrect={false}
          textContentType="emailAddress"
        />

        <TextInput
          style={styles.input}
          placeholder="Password"
          placeholderTextColor={colors.textTertiary}
          value={password}
          onChangeText={(text) => {
            setPassword(text);
            clearError();
          }}
          secureTextEntry
          autoCapitalize="none"
          autoCorrect={false}
          textContentType="password"
          onSubmitEditing={handleSignIn}
        />

        {errorMessage && <ErrorBanner message={errorMessage} />}

        <TouchableOpacity
          style={[styles.primaryButton, (!email || !password || isSigningIn) && styles.buttonDisabled]}
          onPress={handleSignIn}
          disabled={!email || !password || isSigningIn}
        >
          {isSigningIn ? (
            <View style={styles.buttonRow}>
              <ActivityIndicator size="small" color="#0d0b1a" />
              <Text style={styles.buttonText}>Signing In...</Text>
            </View>
          ) : (
            <Text style={styles.buttonText}>Sign In</Text>
          )}
        </TouchableOpacity>

        {/* Divider */}
        <View style={styles.dividerRow}>
          <View style={styles.divider} />
          <Text style={styles.dividerText}>or</Text>
          <View style={styles.divider} />
        </View>

        <TouchableOpacity
          style={styles.secondaryButton}
          onPress={() => router.push('/(auth)/signup')}
        >
          <Text style={styles.secondaryButtonText}>Create Account</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.spacer} />

      <View style={styles.bottomRow}>
        <TouchableOpacity onPress={() => router.push('/(auth)/signup')}>
          <Text style={styles.linkText}>Create Account</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={handleResetPassword} disabled={!email}>
          <Text style={[styles.linkTextSmall, !email && styles.linkDisabled]}>
            Forgot Password?
          </Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
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
  form: {
    gap: spacing.lg,
  },
  input: {
    backgroundColor: colors.surface,
    color: colors.text,
    borderRadius: 8,
    padding: 14,
    fontSize: 16,
    borderWidth: 1,
    borderColor: colors.border,
  },
  primaryButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
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
  secondaryButton: {
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.primary,
  },
  secondaryButtonText: {
    color: colors.primary,
    fontSize: 16,
    fontWeight: '600',
  },
  dividerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 4,
  },
  divider: {
    flex: 1,
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.divider,
  },
  dividerText: {
    color: colors.textTertiary,
    fontSize: 12,
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
  bottomRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingBottom: spacing.lg,
  },
  linkText: {
    color: colors.primary,
    fontSize: 14,
  },
  linkTextSmall: {
    color: colors.primary,
    fontSize: 12,
  },
  linkDisabled: {
    opacity: 0.4,
  },
});
