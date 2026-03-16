import React, { useState, useEffect, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Platform,
} from 'react-native';
import { useRouter } from 'expo-router';
import { ErrorBanner } from '@/components/ErrorBanner';
import { colors, spacing, fonts } from '@/constants/theme';
import * as authService from '@/services/auth';
import type { ConfirmationResult, RecaptchaVerifier } from '@/services/auth';

export default function PhoneLoginScreen() {
  const router = useRouter();
  const [phoneNumber, setPhoneNumber] = useState('');
  const [code, setCode] = useState('');
  const [step, setStep] = useState<'phone' | 'code'>('phone');
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const confirmationRef = useRef<ConfirmationResult | null>(null);
  const recaptchaRef = useRef<RecaptchaVerifier | null>(null);

  useEffect(() => {
    if (Platform.OS !== 'web') return;

    // Create a real DOM div for reCAPTCHA since RN Web's View nativeID won't work
    let container = document.getElementById('recaptcha-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'recaptcha-container';
      document.body.appendChild(container);
    }

    recaptchaRef.current = authService.createRecaptchaVerifier('recaptcha-container');

    return () => {
      recaptchaRef.current?.clear();
      recaptchaRef.current = null;
      container?.remove();
    };
  }, []);

  const handleSendCode = async () => {
    const formatted = phoneNumber.trim().startsWith('+')
      ? phoneNumber.trim()
      : `+1${phoneNumber.trim()}`;

    if (formatted.length < 10) {
      setErrorMessage('Please enter a valid phone number.');
      return;
    }

    setErrorMessage(null);
    setIsLoading(true);

    try {
      if (!recaptchaRef.current) {
        recaptchaRef.current = authService.createRecaptchaVerifier('recaptcha-container');
      }
      confirmationRef.current = await authService.sendPhoneCode(formatted, recaptchaRef.current);
      setStep('code');
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to send verification code.');
      // Recreate recaptcha on failure
      try { recaptchaRef.current?.clear(); } catch {}
      recaptchaRef.current = authService.createRecaptchaVerifier('recaptcha-container');
    } finally {
      setIsLoading(false);
    }
  };

  const handleVerifyCode = async () => {
    if (!code.trim() || !confirmationRef.current) return;

    setErrorMessage(null);
    setIsLoading(true);

    try {
      await confirmationRef.current.confirm(code.trim());
      // Auth state listener in useAuth will handle the rest
    } catch (error: any) {
      setErrorMessage(error.message || 'Invalid verification code.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.spacer} />

      <Text style={styles.title}>Phone Sign In</Text>
      <Text style={styles.subtitle}>
        {step === 'phone'
          ? 'Enter your phone number to receive a code'
          : 'Enter the 6-digit code sent to your phone'}
      </Text>

      {errorMessage && <ErrorBanner message={errorMessage} />}

      {step === 'phone' ? (
        <>
          <TextInput
            style={styles.input}
            placeholder="Phone number (e.g. +15551234567)"
            placeholderTextColor={colors.textTertiary}
            value={phoneNumber}
            onChangeText={setPhoneNumber}
            keyboardType="phone-pad"
            textContentType="telephoneNumber"
            editable={!isLoading}
            accessibilityLabel="Phone number"
          />

          <TouchableOpacity
            style={[styles.primaryButton, isLoading && styles.buttonDisabled]}
            onPress={handleSendCode}
            disabled={isLoading}
            accessibilityLabel="Send verification code"
            accessibilityRole="button"
          >
            {isLoading ? (
              <View style={styles.buttonRow}>
                <ActivityIndicator size="small" color="#0d0b1a" />
                <Text style={styles.buttonText}>Sending...</Text>
              </View>
            ) : (
              <Text style={styles.buttonText}>Send Code</Text>
            )}
          </TouchableOpacity>
        </>
      ) : (
        <>
          <TextInput
            style={styles.input}
            placeholder="6-digit code"
            placeholderTextColor={colors.textTertiary}
            value={code}
            onChangeText={setCode}
            keyboardType="number-pad"
            textContentType="oneTimeCode"
            maxLength={6}
            editable={!isLoading}
            autoFocus
            accessibilityLabel="Verification code"
          />

          <TouchableOpacity
            style={[styles.primaryButton, isLoading && styles.buttonDisabled]}
            onPress={handleVerifyCode}
            disabled={isLoading}
            accessibilityLabel="Verify code"
            accessibilityRole="button"
          >
            {isLoading ? (
              <View style={styles.buttonRow}>
                <ActivityIndicator size="small" color="#0d0b1a" />
                <Text style={styles.buttonText}>Verifying...</Text>
              </View>
            ) : (
              <Text style={styles.buttonText}>Verify Code</Text>
            )}
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.backLink}
            onPress={() => {
              setStep('phone');
              setCode('');
              setErrorMessage(null);
            }}
            disabled={isLoading}
          >
            <Text style={styles.linkText}>Use a different number</Text>
          </TouchableOpacity>
        </>
      )}

      <TouchableOpacity
        style={styles.backLink}
        onPress={() => router.back()}
        disabled={isLoading}
      >
        <Text style={styles.linkText}>Back to Sign In</Text>
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
