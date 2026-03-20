import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Platform } from 'react-native';
import { useRouter, useFocusEffect } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '@/hooks/useAuth';
import { Game } from '@/models/types';
import * as firestoreService from '@/services/firestore';
import { colors, spacing, fonts } from '@/constants/theme';

export default function HomeScreen() {
  const router = useRouter();
  const { authState, currentUserId } = useAuth();
  const [activeGame, setActiveGame] = useState<Game | null>(null);
  const [, setCheckingActiveGame] = useState(true);

  const checkForActiveGame = useCallback(async () => {
    if (!currentUserId) return;
    try {
      const game = await firestoreService.getActiveGame(currentUserId);
      setActiveGame(game);
    } catch (error) {
      console.warn('Failed to check active game:', error);
    } finally {
      setCheckingActiveGame(false);
    }
  }, [currentUserId]);

  // Run on mount and whenever auth changes
  useEffect(() => {
    if (authState === 'authenticated') {
      checkForActiveGame();
    }
  }, [authState, checkForActiveGame]);

  // Re-check when screen regains focus (native back navigation)
  useFocusEffect(
    useCallback(() => {
      if (authState === 'authenticated') {
        checkForActiveGame();
      }
    }, [authState, checkForActiveGame]),
  );

  // On web, also listen for popstate (browser back button) and visibility changes
  useEffect(() => {
    if (Platform.OS !== 'web') return;

    const handlePopState = () => {
      if (authState === 'authenticated') {
        checkForActiveGame();
      }
    };

    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, [authState, checkForActiveGame]);

  if (authState !== 'authenticated') return null;

  const handleRejoin = () => {
    if (!activeGame) return;
    if (activeGame.state === 'in_progress') {
      router.push({
        pathname: '/(app)/game/[gameId]',
        params: { gameId: activeGame.id },
      });
    } else {
      router.push({
        pathname: '/(app)/lobby/[gameId]',
        params: {
          gameId: activeGame.id,
          isHost: activeGame.host_id === currentUserId ? 'true' : 'false',
        },
      });
    }
  };

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

      {/* Rejoin active game banner */}
      {activeGame && (
        <TouchableOpacity
          style={styles.rejoinBanner}
          onPress={handleRejoin}
          accessibilityLabel={
            activeGame?.state === 'in_progress' ? 'Rejoin game in progress' : 'Rejoin waiting game'
          }
          accessibilityRole="button"
        >
          <View style={styles.rejoinIcon}>
            <Ionicons name="game-controller" size={20} color={colors.primaryBright} />
          </View>
          <View style={styles.rejoinInfo}>
            <Text style={styles.rejoinTitle}>
              {activeGame.state === 'in_progress' ? 'Game in Progress' : 'Game Waiting'}
            </Text>
            <Text style={styles.rejoinSubtitle}>Tap to rejoin</Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color={colors.primary} />
        </TouchableOpacity>
      )}

      <TouchableOpacity
        style={styles.primaryButton}
        onPress={() => router.push('/(app)/create-game')}
        accessibilityLabel="Create game"
        accessibilityRole="button"
      >
        <Text style={styles.primaryButtonText}>Create Game</Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={styles.secondaryButton}
        onPress={() => router.push('/(app)/join-game')}
        accessibilityLabel="Join game"
        accessibilityRole="button"
      >
        <Text style={styles.secondaryButtonText}>Join Game</Text>
      </TouchableOpacity>

      <View style={styles.spacer} />

      {/* Bottom navigation */}
      <View style={styles.bottomNav}>
        <TouchableOpacity
          style={styles.navItem}
          onPress={() => router.push('/(app)/history')}
          accessibilityLabel="History"
          accessibilityRole="button"
        >
          <Ionicons name="time" size={24} color={colors.textSecondary} />
          <Text style={styles.navLabel}>History</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.navItem}
          onPress={() => router.push('/(app)/friends')}
          accessibilityLabel="Friends"
          accessibilityRole="button"
        >
          <Ionicons name="people" size={24} color={colors.textSecondary} />
          <Text style={styles.navLabel}>Friends</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.navItem}
          onPress={() => router.push('/(app)/profile')}
          accessibilityLabel="Profile"
          accessibilityRole="button"
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
  rejoinBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.borderAccent,
    borderRadius: 12,
    padding: spacing.md,
    gap: 12,
    width: '100%',
    maxWidth: 280,
  },
  rejoinIcon: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(201, 168, 76, 0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  rejoinInfo: {
    flex: 1,
  },
  rejoinTitle: {
    color: colors.primaryBright,
    fontSize: 14,
    fontWeight: '600',
  },
  rejoinSubtitle: {
    color: colors.textSecondary,
    fontSize: 12,
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
