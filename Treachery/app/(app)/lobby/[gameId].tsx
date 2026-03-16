import React, { useEffect } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  FlatList,
  ActivityIndicator,
  Alert,
  Share,
  Platform,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as Clipboard from 'expo-clipboard';
import { useAuth } from '@/hooks/useAuth';
import { useLobby } from '@/hooks/useLobby';
import { ErrorBanner } from '@/components/ErrorBanner';
import { LoadingScreen } from '@/components/LoadingScreen';
import { ConnectionBanner } from '@/components/ConnectionBanner';
import { colors, spacing, fonts } from '@/constants/theme';
import { MINIMUM_PLAYER_COUNT } from '@/constants/roles';

export default function LobbyScreen() {
  const { gameId, isHost: isHostParam } = useLocalSearchParams<{
    gameId: string;
    isHost: string;
  }>();
  const router = useRouter();
  const { currentUserId } = useAuth();
  const isHost = isHostParam === 'true';

  const {
    game,
    players,
    errorMessage,
    isStartingGame,
    isGameDisbanded,
    isGameStarted,
    canStartGame,
    startGame,
    leaveGame,
  } = useLobby(gameId!, isHost);

  // On web, intercept browser back button — prevent accidental lobby exit
  useEffect(() => {
    if (Platform.OS !== 'web') return;

    window.history.pushState(null, '', window.location.href);

    const handlePopState = () => {
      window.history.pushState(null, '', window.location.href);
    };

    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, []);

  // Navigate to game board when game starts
  useEffect(() => {
    if (isGameStarted) {
      router.replace({
        pathname: '/(app)/game/[gameId]',
        params: { gameId: gameId! },
      });
    }
  }, [isGameStarted, gameId, router]);

  // Handle game disbanded
  useEffect(() => {
    if (isGameDisbanded && !isHost) {
      Alert.alert('Game Disbanded', 'The host has left and the game was closed.', [
        { text: 'OK', onPress: () => router.replace('/(app)') },
      ]);
    }
  }, [isGameDisbanded, isHost, router]);

  const handleShare = async () => {
    const message = `Join my Treachery game! Code: ${game?.code}`;
    if (Platform.OS === 'web') {
      await Clipboard.setStringAsync(game?.code ?? '');
      Alert.alert('Copied!', 'Game code copied to clipboard.');
    } else {
      await Share.share({ message });
    }
  };

  const handleLeave = () => {
    Alert.alert('Leave Game', 'Are you sure you want to leave?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Leave',
        style: 'destructive',
        onPress: async () => {
          if (currentUserId) {
            await leaveGame(currentUserId);
            router.replace('/(app)');
          }
        },
      },
    ]);
  };

  if (!game && !errorMessage && !isGameDisbanded) {
    return <LoadingScreen message="Loading lobby..." />;
  }

  if (isGameDisbanded) {
    return (
      <View style={styles.centerContainer}>
        <Ionicons name="close-circle" size={48} color={colors.error} />
        <Text style={styles.disbandedTitle}>Game Disbanded</Text>
        <Text style={styles.disbandedText}>
          The host has left and the game was closed.
        </Text>
        <TouchableOpacity
          style={styles.primaryButton}
          onPress={() => router.replace('/(app)')}
          accessibilityLabel="Return home"
          accessibilityRole="button"
        >
          <Text style={styles.buttonText}>Return Home</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <ConnectionBanner />

      {/* Game code display - ornate card frame */}
      {game && (
        <View style={styles.codeSection}>
          <View style={styles.codeFrame}>
            <View style={styles.codeTrim} />
            <Text style={styles.codeLabel}>Game Code</Text>
            <Text style={styles.codeText}>{game.code}</Text>
            <TouchableOpacity
              style={styles.shareButton}
              onPress={handleShare}
              accessibilityLabel="Share game code"
              accessibilityRole="button"
            >
              <Ionicons name="share-outline" size={14} color={colors.primary} />
              <Text style={styles.shareText}>Share Code</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {/* Ornate divider */}
      <View style={styles.ornateDividerRow}>
        <View style={styles.ornateLine} />
        <Text style={styles.ornateDiamond}>&#9670;</Text>
        <View style={styles.ornateLine} />
      </View>

      {/* Player list */}
      <Text style={styles.sectionTitle}>
        Players ({players.length}/{game?.max_players ?? 0})
      </Text>

      {players.length === 0 ? (
        <Text style={styles.waitingText}>Waiting for players to join...</Text>
      ) : (
        <FlatList
          data={players}
          keyExtractor={(p) => p.id}
          renderItem={({ item }) => (
            <View style={styles.playerRow}>
              <View style={styles.playerIcon}>
                <Ionicons name="person" size={14} color={colors.textSecondary} />
              </View>
              <Text style={[styles.playerName, item.user_id === game?.host_id && styles.bold]}>
                {item.display_name}
              </Text>
              {item.user_id === game?.host_id && (
                <View style={styles.hostBadge}>
                  <Text style={styles.hostBadgeText}>Host</Text>
                </View>
              )}
            </View>
          )}
          style={styles.list}
        />
      )}

      {!isHost && (
        <View style={styles.waitingRow}>
          <ActivityIndicator size="small" color={colors.primary} />
          <Text style={styles.waitingForHost}>
            Waiting for host to start the game...
          </Text>
        </View>
      )}

      {errorMessage && <ErrorBanner message={errorMessage} />}

      {/* Bottom buttons */}
      <View style={styles.bottomButtons}>
        {isHost && (
          <>
            <TouchableOpacity
              style={[styles.primaryButton, (!canStartGame || isStartingGame) && styles.buttonDisabled]}
              onPress={startGame}
              disabled={!canStartGame || isStartingGame}
              accessibilityLabel={isStartingGame ? 'Starting game' : 'Start game'}
              accessibilityRole="button"
            >
              {isStartingGame ? (
                <View style={styles.buttonRow}>
                  <ActivityIndicator size="small" color="#0d0b1a" />
                  <Text style={styles.buttonText}>Starting...</Text>
                </View>
              ) : (
                <Text style={styles.buttonText}>Start Game</Text>
              )}
            </TouchableOpacity>

            {!canStartGame && players.length < MINIMUM_PLAYER_COUNT && (
              <Text style={styles.minPlayersText}>
                Need at least {MINIMUM_PLAYER_COUNT} players to start
              </Text>
            )}
          </>
        )}

        <TouchableOpacity
          style={styles.leaveButton}
          onPress={handleLeave}
          accessibilityLabel="Leave game"
          accessibilityRole="button"
        >
          <Text style={styles.leaveText}>Leave Game</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  centerContainer: {
    flex: 1,
    backgroundColor: colors.background,
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.lg,
    gap: 12,
  },
  codeSection: {
    padding: spacing.lg,
  },
  codeFrame: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderWidth: 2,
    borderColor: colors.borderAccent,
    borderRadius: 12,
    paddingBottom: 16,
    overflow: 'hidden',
  },
  codeTrim: {
    height: 3,
    backgroundColor: colors.primary,
    alignSelf: 'stretch',
    marginBottom: 12,
  },
  codeLabel: {
    color: colors.textSecondary,
    fontSize: 11,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1.5,
  },
  codeText: {
    color: colors.primaryBright,
    fontSize: 48,
    fontWeight: 'bold',
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    letterSpacing: 8,
    marginVertical: 4,
  },
  shareButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingTop: 4,
  },
  shareText: {
    color: colors.primary,
    fontSize: 12,
  },
  ornateDividerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.lg,
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
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1.5,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.sm,
  },
  waitingText: {
    color: colors.textTertiary,
    fontSize: 14,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    fontStyle: 'italic',
  },
  list: {
    flex: 1,
  },
  playerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.lg,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  playerIcon: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 10,
  },
  playerName: {
    color: colors.text,
    fontSize: 16,
    flex: 1,
  },
  bold: {
    fontWeight: '600',
  },
  hostBadge: {
    backgroundColor: 'rgba(201, 168, 76, 0.15)',
    borderWidth: 1,
    borderColor: 'rgba(201, 168, 76, 0.3)',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
  },
  hostBadgeText: {
    color: colors.primary,
    fontSize: 12,
    fontWeight: '500',
  },
  waitingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
  },
  waitingForHost: {
    color: colors.textSecondary,
    fontSize: 14,
    fontStyle: 'italic',
  },
  bottomButtons: {
    padding: spacing.lg,
    gap: 12,
    alignItems: 'center',
  },
  primaryButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    width: '100%',
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
  minPlayersText: {
    color: colors.textTertiary,
    fontSize: 12,
    fontStyle: 'italic',
  },
  leaveButton: {
    padding: 10,
  },
  leaveText: {
    color: colors.destructive,
    fontSize: 16,
  },
  disbandedTitle: {
    color: colors.text,
    fontSize: 20,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  disbandedText: {
    color: colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
  },
});
