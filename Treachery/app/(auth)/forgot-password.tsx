import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
} from 'react-native';
import { useRouter } from 'expo-router';
import { ErrorBanner } from '@/components/ErrorBanner';
import { NoticeDialog } from '@/components/NoticeDialog';
import { colors, spacing, fonts } from '@/constants/theme';
import * as authService from '@/services/auth';

export default function ForgotPasswordScreen() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [showSentNotice, setShowSentNotice] = useState(false);

  const handleReset = async () => {
    if (!email.trim()) return;
    setErrorMessage(null);
    setIsLoading(true);

    try {
      // Called directly rather than through useAuth so success/failure comes
      // from this await — the hook reports errors via state we'd only read on
      // the next render, which made a failed send report "Email Sent".
      await authService.resetPassword(email.trim());
      setShowSentNotice(true);
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to send reset email.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.spacer} />

      <Text style={styles.title}>Reset Password</Text>
      <Text style={styles.subtitle}>Enter your email and we&apos;ll send you a reset link.</Text>

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
        editable={!isLoading}
        accessibilityLabel="Email"
      />

      <TouchableOpacity
        style={[styles.primaryButton, isLoading && styles.buttonDisabled]}
        onPress={handleReset}
        disabled={isLoading}
        accessibilityLabel="Send reset email"
        accessibilityRole="button"
      >
        {isLoading ? (
          <View style={styles.buttonRow}>
            <ActivityIndicator size="small" color="#0d0b1a" />
            <Text style={styles.buttonText}>Sending...</Text>
          </View>
        ) : (
          <Text style={styles.buttonText}>Send Reset Link</Text>
        )}
      </TouchableOpacity>

      <TouchableOpacity style={styles.backLink} onPress={() => router.back()} disabled={isLoading}>
        <Text style={styles.linkText}>Back to Sign In</Text>
      </TouchableOpacity>

      <View style={styles.spacer} />

      <NoticeDialog
        visible={showSentNotice}
        title="Email Sent"
        message="Check your inbox for a password reset link."
        dismissAccessibilityLabel="Dismiss email sent notice"
        onDismiss={() => {
          setShowSentNotice(false);
          router.back();
        }}
      />
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
    marginBottom: spacing.xl,
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
  backLink: {
    alignItems: 'center',
    marginTop: spacing.lg,
  },
  linkText: {
    color: colors.primary,
    fontSize: 14,
  },
});
