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
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '@/hooks/useAuth';
import { ErrorBanner } from '@/components/ErrorBanner';
import { colors, spacing } from '@/constants/theme';

export default function SignUpScreen() {
  const { signUp, errorMessage, clearError } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [validationError, setValidationError] = useState<string | null>(null);
  const [isCreating, setIsCreating] = useState(false);

  const passwordsMatch = password.length > 0 && password === confirmPassword;

  const handleCreate = async () => {
    if (password !== confirmPassword) {
      setValidationError('Passwords do not match.');
      return;
    }
    if (password.length < 6) {
      setValidationError('Password must be at least 6 characters.');
      return;
    }
    setValidationError(null);
    setIsCreating(true);
    await signUp(email, password);
    setIsCreating(false);
  };

  const displayError = validationError || errorMessage;

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
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
            setValidationError(null);
          }}
          secureTextEntry
          autoCapitalize="none"
          textContentType="newPassword"
        />

        <TextInput
          style={styles.input}
          placeholder="Confirm Password"
          placeholderTextColor={colors.textTertiary}
          value={confirmPassword}
          onChangeText={(text) => {
            setConfirmPassword(text);
            setValidationError(null);
          }}
          secureTextEntry
          autoCapitalize="none"
          textContentType="newPassword"
        />

        {/* Password match indicator */}
        {confirmPassword.length > 0 && (
          <View style={styles.matchRow}>
            <Ionicons
              name={passwordsMatch ? 'checkmark-circle' : 'close-circle'}
              size={14}
              color={passwordsMatch ? colors.success : colors.error}
            />
            <Text style={{ color: passwordsMatch ? colors.success : colors.error, fontSize: 12 }}>
              {passwordsMatch ? 'Passwords match' : 'Passwords do not match'}
            </Text>
          </View>
        )}

        {displayError && <ErrorBanner message={displayError} />}

        <TouchableOpacity
          style={[
            styles.primaryButton,
            (!email || !password || !confirmPassword || isCreating) && styles.buttonDisabled,
          ]}
          onPress={handleCreate}
          disabled={!email || !password || !confirmPassword || isCreating}
        >
          {isCreating ? (
            <View style={styles.buttonRow}>
              <ActivityIndicator size="small" color="#fff" />
              <Text style={styles.buttonText}>Creating Account...</Text>
            </View>
          ) : (
            <Text style={styles.buttonText}>Create Account</Text>
          )}
        </TouchableOpacity>

        {password.length === 0 && (
          <Text style={styles.hint}>Password must be at least 6 characters</Text>
        )}
      </View>

      <View style={{ flex: 1 }} />
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: spacing.lg,
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
  matchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
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
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
  },
  hint: {
    color: colors.textSecondary,
    fontSize: 11,
  },
});
