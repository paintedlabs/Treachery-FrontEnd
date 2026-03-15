import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Alert,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '@/hooks/useAuth';
import { ErrorBanner } from '@/components/ErrorBanner';
import { colors, spacing } from '@/constants/theme';

export default function ForgotPasswordScreen() {
  const router = useRouter();
  const { resetPassword, errorMessage } = useAuth();
  const [email, setEmail] = useState('');
  const [isSending, setIsSending] = useState(false);

  const handleReset = async () => {
    if (!email) return;
    setIsSending(true);
    await resetPassword(email);
    setIsSending(false);
    if (!errorMessage) {
      Alert.alert('Email Sent', 'Check your email for a password reset link.', [
        { text: 'OK', onPress: () => router.back() },
      ]);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.description}>
        Enter your email address and we'll send you a link to reset your password.
      </Text>

      <TextInput
        style={styles.input}
        placeholder="Email"
        placeholderTextColor={colors.textTertiary}
        value={email}
        onChangeText={setEmail}
        keyboardType="email-address"
        autoCapitalize="none"
        autoCorrect={false}
      />

      {errorMessage && <ErrorBanner message={errorMessage} />}

      <TouchableOpacity
        style={[styles.button, (!email || isSending) && styles.buttonDisabled]}
        onPress={handleReset}
        disabled={!email || isSending}
      >
        <Text style={styles.buttonText}>
          {isSending ? 'Sending...' : 'Reset Password'}
        </Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: spacing.lg,
    gap: spacing.lg,
  },
  description: {
    color: colors.textSecondary,
    fontSize: 14,
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
  button: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
  },
});
