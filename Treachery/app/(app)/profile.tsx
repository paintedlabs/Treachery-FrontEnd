import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  ActivityIndicator,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '@/hooks/useAuth';
import { useProfile } from '@/hooks/useProfile';
import { StatBox } from '@/components/StatBox';
import { ErrorBanner } from '@/components/ErrorBanner';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { Role } from '@/models/types';
import { colors, spacing, fonts } from '@/constants/theme';

export default function ProfileScreen() {
  const router = useRouter();
  const { currentUserId, signOut } = useAuth();
  const { user, gameStats, errorMessage, isLoading, isSaving, saveName } =
    useProfile(currentUserId);

  const [isEditing, setIsEditing] = useState(false);
  const [editedName, setEditedName] = useState('');

  const handleEdit = () => {
    setEditedName(user?.display_name ?? '');
    setIsEditing(true);
  };

  const handleSave = async () => {
    await saveName(editedName);
    setIsEditing(false);
  };

  const handleSignOut = async () => {
    await signOut();
    // AuthRedirect in _layout.tsx handles navigation to login
  };

  const formatDate = (timestamp: any) => {
    if (!timestamp) return '';
    const date = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
    return date.toLocaleDateString();
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      {/* Profile section */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Profile</Text>

        {user ? (
          <View style={styles.card}>
            <View style={styles.row}>
              <Text style={styles.label}>Display Name</Text>
              {isEditing ? (
                <TextInput
                  style={styles.nameInput}
                  value={editedName}
                  onChangeText={setEditedName}
                  autoCapitalize="words"
                  accessibilityLabel="Display name"
                  accessibilityRole="text"
                />
              ) : (
                <Text style={styles.value}>{user.display_name}</Text>
              )}
            </View>

            <View style={[styles.row, { borderBottomWidth: 0 }]}>
              <Text style={styles.label}>Member Since</Text>
              <Text style={styles.value}>{formatDate(user.created_at)}</Text>
            </View>
          </View>
        ) : (
          <ActivityIndicator color={colors.primary} />
        )}

        {/* Edit/Save button */}
        {isEditing ? (
          <TouchableOpacity
            style={[styles.editButton, (isSaving || !editedName.trim()) && styles.buttonDisabled]}
            onPress={handleSave}
            disabled={isSaving || !editedName.trim()}
            accessibilityLabel={isSaving ? 'Saving display name' : 'Save display name'}
            accessibilityRole="button"
          >
            <Text style={styles.editButtonText}>
              {isSaving ? 'Saving...' : 'Save'}
            </Text>
          </TouchableOpacity>
        ) : (
          <TouchableOpacity
            style={styles.editButton}
            onPress={handleEdit}
            disabled={!user}
            accessibilityLabel="Edit display name"
            accessibilityRole="button"
          >
            <Text style={styles.editButtonText}>Edit</Text>
          </TouchableOpacity>
        )}
      </View>

      {/* Ornate divider */}
      <View style={styles.ornateDivider}>
        <View style={styles.ornateLine} />
        <Text style={styles.ornateDiamond}>&#9670;</Text>
        <View style={styles.ornateLine} />
      </View>

      {/* Game stats */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Game Stats</Text>

        {isLoading && !gameStats ? (
          <ActivityIndicator color={colors.primary} />
        ) : (
          <View style={styles.card}>
            <View style={styles.statsRow}>
              <StatBox value={`${gameStats?.totalGames ?? 0}`} label="Games" color={colors.text} />
              <StatBox value={`${gameStats?.wins ?? 0}`} label="Wins" color={colors.success} />
              <StatBox value={`${gameStats?.losses ?? 0}`} label="Losses" color={colors.error} />
              <StatBox value={gameStats?.winRateText ?? '—'} label="Win %" color={colors.primary} />
            </View>

            {/* Role breakdown */}
            {gameStats && Object.keys(gameStats.roleBreakdown).length > 0 && (
              <View style={styles.roleBreakdown}>
                <Text style={styles.subLabel}>Roles Played</Text>
                {(Object.entries(gameStats.roleBreakdown) as [Role, number][])
                  .sort(([, a], [, b]) => b - a)
                  .map(([role, count]) => (
                    <View key={role} style={styles.roleRow}>
                      <View style={[styles.roleDot, { backgroundColor: ROLE_COLORS[role] }]} />
                      <Text style={styles.roleText}>{ROLE_DISPLAY_NAMES[role]}</Text>
                      <Text style={[styles.roleCount, { color: ROLE_COLORS[role] }]}>{count}</Text>
                    </View>
                  ))}
              </View>
            )}

            <TouchableOpacity
              style={styles.historyLink}
              onPress={() => router.push('/(app)/history')}
              accessibilityLabel="View game history"
              accessibilityRole="link"
            >
              <Text style={styles.linkText}>View Game History</Text>
            </TouchableOpacity>
          </View>
        )}
      </View>

      {/* Friends */}
      {user && user.friend_ids && (
        <View style={styles.section}>
          <TouchableOpacity
            style={styles.card}
            onPress={() => router.push('/(app)/friends')}
            accessibilityLabel={`Friends: ${user.friend_ids?.length ?? 0}`}
            accessibilityRole="link"
          >
            <View style={[styles.row, { borderBottomWidth: 0 }]}>
              <Text style={styles.label}>Friends</Text>
              <Text style={styles.value}>{user.friend_ids?.length ?? 0}</Text>
            </View>
          </TouchableOpacity>
        </View>
      )}

      {errorMessage && <ErrorBanner message={errorMessage} />}

      {/* Sign out */}
      <TouchableOpacity
        style={styles.signOutButton}
        onPress={handleSignOut}
        accessibilityLabel="Sign out"
        accessibilityRole="button"
      >
        <Text style={styles.signOutText}>Sign Out</Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    padding: spacing.lg,
    gap: spacing.xl,
    paddingBottom: 40,
  },
  section: {
    gap: spacing.sm,
  },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1.5,
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 14,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  label: {
    color: colors.text,
    fontSize: 16,
  },
  value: {
    color: colors.textSecondary,
    fontSize: 16,
  },
  nameInput: {
    color: colors.text,
    fontSize: 16,
    textAlign: 'right',
    flex: 1,
    marginLeft: 16,
    borderBottomWidth: 1,
    borderBottomColor: colors.primary,
    padding: 4,
  },
  editButton: {
    alignSelf: 'flex-end',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  editButtonText: {
    color: colors.primary,
    fontSize: 16,
    fontWeight: '600',
  },
  ornateDivider: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
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
  statsRow: {
    flexDirection: 'row',
    padding: 14,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  roleBreakdown: {
    padding: 14,
    gap: 6,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  subLabel: {
    color: colors.textSecondary,
    fontSize: 11,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginBottom: 4,
  },
  roleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  roleDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  roleText: {
    color: colors.text,
    fontSize: 14,
    flex: 1,
  },
  roleCount: {
    fontSize: 14,
    fontWeight: '600',
    fontFamily: fonts.serif,
  },
  historyLink: {
    padding: 14,
  },
  linkText: {
    color: colors.primary,
    fontSize: 16,
  },
  signOutButton: {
    backgroundColor: colors.surface,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(196, 60, 60, 0.3)',
    padding: 14,
    alignItems: 'center',
  },
  signOutText: {
    color: colors.destructive,
    fontSize: 16,
  },
});
