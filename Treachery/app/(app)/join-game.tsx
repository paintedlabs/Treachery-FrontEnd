import React, { useState } from 'react';
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
import { Timestamp } from 'firebase/firestore';
import { useAuth } from '@/hooks/useAuth';
import { ErrorBanner } from '@/components/ErrorBanner';
import * as firestoreService from '@/services/firestore';
import { Player } from '@/models/types';
import { colors, spacing, fonts } from '@/constants/theme';

function generateId(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export default function JoinGameScreen() {
  const router = useRouter();
  const { currentUserId } = useAuth();
  const [gameCode, setGameCode] = useState('');
  const [isJoining, setIsJoining] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleJoin = async () => {
    if (!currentUserId || gameCode.length < 4) return;
    setIsJoining(true);
    setErrorMessage(null);

    try {
      const game = await firestoreService.getGameByCode(gameCode);
      if (!game) throw new Error('No game found with that code.');
      if (game.state !== 'waiting') throw new Error('This game has already started.');

      const existingPlayers = await firestoreService.getPlayers(game.id);
      if (existingPlayers.length >= game.max_players) throw new Error('This game is full.');

      // Check if already in game
      if (existingPlayers.some((p) => p.user_id === currentUserId)) {
        router.replace({
          pathname: '/(app)/lobby/[gameId]',
          params: { gameId: game.id, isHost: 'false' },
        });
        setIsJoining(false);
        return;
      }

      const user = await firestoreService.getUser(currentUserId);
      const player: Player = {
        id: generateId(),
        order_id: existingPlayers.length,
        user_id: currentUserId,
        display_name: user?.display_name ?? 'Player',
        role: null,
        identity_card_id: null,
        life_total: game.starting_life,
        is_eliminated: false,
        is_unveiled: false,
        joined_at: Timestamp.now(),
        player_color: null,
        commander_name: null,
      };
      await firestoreService.addPlayer(player, game.id);
      await firestoreService.addPlayerIdToGame(game.id, currentUserId);

      router.replace({
        pathname: '/(app)/lobby/[gameId]',
        params: { gameId: game.id, isHost: 'false' },
      });
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to join game.');
    }
    setIsJoining(false);
  };

  return (
    <View style={styles.container}>
      <Text style={styles.subtitle}>Enter the 4-character game code</Text>

      {/* Card-frame style code input */}
      <View style={styles.codeFrame}>
        <View style={styles.codeTrim} />
        <TextInput
          style={styles.codeInput}
          placeholder="ABCD"
          placeholderTextColor={colors.textTertiary}
          value={gameCode}
          onChangeText={(text) => setGameCode(text.toUpperCase().slice(0, 4))}
          autoCapitalize="characters"
          autoCorrect={false}
          maxLength={4}
          textAlign="center"
          accessibilityLabel="Game code"
          accessibilityRole="text"
          accessibilityHint="Enter the 4-character game code"
        />
      </View>

      {errorMessage && <ErrorBanner message={errorMessage} />}

      <TouchableOpacity
        style={[styles.joinButton, (gameCode.length < 4 || isJoining) && styles.buttonDisabled]}
        onPress={handleJoin}
        disabled={gameCode.length < 4 || isJoining}
        accessibilityLabel={isJoining ? 'Joining game' : 'Join game'}
        accessibilityRole="button"
      >
        {isJoining ? (
          <View style={styles.buttonRow}>
            <ActivityIndicator size="small" color="#0d0b1a" />
            <Text style={styles.buttonText}>Joining...</Text>
          </View>
        ) : (
          <Text style={styles.buttonText}>Join Game</Text>
        )}
      </TouchableOpacity>

      <View style={{ flex: 1 }} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: spacing.lg,
    gap: spacing.xl,
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
  codeFrame: {
    backgroundColor: colors.surface,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: colors.borderAccent,
    overflow: 'hidden',
  },
  codeTrim: {
    height: 3,
    backgroundColor: colors.primary,
  },
  codeInput: {
    color: colors.primaryBright,
    padding: 20,
    fontSize: 36,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    fontWeight: 'bold',
    letterSpacing: 16,
    textAlign: 'center',
  },
  joinButton: {
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
});
