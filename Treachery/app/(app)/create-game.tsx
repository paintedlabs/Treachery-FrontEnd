import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
} from 'react-native';
import { useRouter } from 'expo-router';
import { Timestamp } from 'firebase/firestore';
import { useAuth } from '@/hooks/useAuth';
import { RoleBadge } from '@/components/RoleBadge';
import { ErrorBanner } from '@/components/ErrorBanner';
import * as firestoreService from '@/services/firestore';
import {
  getRoleDistribution,
  MINIMUM_PLAYER_COUNT,
  CODE_CHARACTERS,
} from '@/constants/roles';
import { Game, Player } from '@/models/types';
import { colors, spacing } from '@/constants/theme';

function generateId(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export default function CreateGameScreen() {
  const router = useRouter();
  const { currentUserId } = useAuth();
  const [maxPlayers, setMaxPlayers] = useState(MINIMUM_PLAYER_COUNT);
  const [startingLife, setStartingLife] = useState(40);
  const [isCreating, setIsCreating] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const dist = getRoleDistribution(maxPlayers);

  const generateUniqueCode = async (): Promise<string> => {
    for (let i = 0; i < 10; i++) {
      let code = '';
      for (let j = 0; j < 4; j++) {
        code += CODE_CHARACTERS[Math.floor(Math.random() * CODE_CHARACTERS.length)];
      }
      const existing = await firestoreService.getGameByCode(code);
      if (!existing) return code;
    }
    throw new Error('Could not generate a unique game code. Please try again.');
  };

  const handleCreate = async () => {
    if (!currentUserId) return;
    setIsCreating(true);
    setErrorMessage(null);

    try {
      const code = await generateUniqueCode();
      const gameId = generateId();

      const game: Game = {
        id: gameId,
        code,
        host_id: currentUserId,
        state: 'waiting',
        max_players: maxPlayers,
        starting_life: startingLife,
        winning_team: null,
        player_ids: [currentUserId],
        created_at: Timestamp.now(),
      };
      await firestoreService.createGame(game);

      // Add host as first player
      const user = await firestoreService.getUser(currentUserId);
      const player: Player = {
        id: generateId(),
        order_id: 0,
        user_id: currentUserId,
        display_name: user?.display_name ?? 'Host',
        role: null,
        identity_card_id: null,
        life_total: startingLife,
        is_eliminated: false,
        is_unveiled: false,
        joined_at: Timestamp.now(),
      };
      await firestoreService.addPlayer(player, gameId);

      router.replace({
        pathname: '/(app)/lobby/[gameId]',
        params: { gameId, isHost: 'true' },
      });
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to create game.');
    }
    setIsCreating(false);
  };

  return (
    <View style={styles.container}>
      {/* Players stepper */}
      <View style={styles.stepperRow}>
        <Text style={styles.stepperLabel}>Players: {maxPlayers}</Text>
        <View style={styles.stepperButtons}>
          <TouchableOpacity
            onPress={() => setMaxPlayers(Math.max(MINIMUM_PLAYER_COUNT, maxPlayers - 1))}
            disabled={maxPlayers <= MINIMUM_PLAYER_COUNT}
          >
            <Text style={[styles.stepperBtn, maxPlayers <= MINIMUM_PLAYER_COUNT && styles.disabled]}>
              −
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            onPress={() => setMaxPlayers(Math.min(8, maxPlayers + 1))}
            disabled={maxPlayers >= 8}
          >
            <Text style={[styles.stepperBtn, maxPlayers >= 8 && styles.disabled]}>+</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* Starting life stepper */}
      <View style={styles.stepperRow}>
        <Text style={styles.stepperLabel}>Starting Life: {startingLife}</Text>
        <View style={styles.stepperButtons}>
          <TouchableOpacity
            onPress={() => setStartingLife(Math.max(20, startingLife - 5))}
            disabled={startingLife <= 20}
          >
            <Text style={[styles.stepperBtn, startingLife <= 20 && styles.disabled]}>−</Text>
          </TouchableOpacity>
          <TouchableOpacity
            onPress={() => setStartingLife(Math.min(60, startingLife + 5))}
            disabled={startingLife >= 60}
          >
            <Text style={[styles.stepperBtn, startingLife >= 60 && styles.disabled]}>+</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* Role distribution */}
      <View style={styles.roleBadges}>
        <RoleBadge count={dist.leaders} role="leader" />
        <RoleBadge count={dist.guardians} role="guardian" />
        <RoleBadge count={dist.assassins} role="assassin" />
        <RoleBadge count={dist.traitors} role="traitor" />
      </View>

      {errorMessage && <ErrorBanner message={errorMessage} />}

      <TouchableOpacity
        style={[styles.createButton, isCreating && styles.buttonDisabled]}
        onPress={handleCreate}
        disabled={isCreating}
      >
        {isCreating ? (
          <View style={styles.buttonRow}>
            <ActivityIndicator size="small" color="#fff" />
            <Text style={styles.buttonText}>Creating...</Text>
          </View>
        ) : (
          <Text style={styles.buttonText}>Create Game</Text>
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
  stepperRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: 8,
    padding: 14,
  },
  stepperLabel: {
    color: colors.text,
    fontSize: 16,
  },
  stepperButtons: {
    flexDirection: 'row',
    gap: 16,
  },
  stepperBtn: {
    color: colors.primary,
    fontSize: 24,
    fontWeight: 'bold',
    minWidth: 30,
    textAlign: 'center',
  },
  disabled: {
    opacity: 0.3,
  },
  roleBadges: {
    flexDirection: 'row',
    justifyContent: 'space-around',
  },
  createButton: {
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
});
