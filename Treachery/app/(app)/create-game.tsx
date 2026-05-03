import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Switch,
  ScrollView,
} from 'react-native';
import { useRouter } from 'expo-router';
import { Timestamp } from 'firebase/firestore';
import { useAuth } from '@/hooks/useAuth';
import { ErrorBanner } from '@/components/ErrorBanner';
import * as firestoreService from '@/services/firestore';
import { CODE_CHARACTERS } from '@/constants/roles';
import { Game, GameMode, Player } from '@/models/types';
import { trackEvent } from '@/services/analytics';
import { colors, spacing, fontSize, contentMaxWidths } from '@/constants/theme';
import { useResponsive } from '@/hooks/useResponsive';

const GAME_MODES: { value: GameMode; label: string }[] = [
  { value: 'treachery', label: 'Treachery' },
  { value: 'planechase', label: 'Planechase' },
  { value: 'treachery_planechase', label: 'Both' },
  { value: 'none', label: 'Life Tracker' },
];

function includesTreachery(mode: GameMode): boolean {
  return mode === 'treachery' || mode === 'treachery_planechase';
}

function includesPlanechase(mode: GameMode): boolean {
  return mode === 'planechase' || mode === 'treachery_planechase';
}

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
  const { isDesktop } = useResponsive();
  const [gameMode, setGameMode] = useState<GameMode>('treachery');
  const [useOwnDeck, setUseOwnDeck] = useState(false);
  const [startingLife, setStartingLife] = useState(40);
  const [isCreating, setIsCreating] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const hasTreachery = includesTreachery(gameMode);
  const hasPlanechase = includesPlanechase(gameMode);

  // Max players is determined by game mode — no user input needed.
  const maxPlayers = hasTreachery ? 8 : 12;

  const handleModeChange = (mode: GameMode) => {
    setGameMode(mode);
    // Reset own deck when planechase is disabled
    if (!includesPlanechase(mode)) setUseOwnDeck(false);
  };

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
        last_activity_at: Timestamp.now(),
        game_mode: gameMode,
        ...(hasPlanechase
          ? {
              planechase: {
                use_own_deck: useOwnDeck,
                current_plane_id: null,
                used_plane_ids: [],
                last_die_roller_id: null,
                die_roll_count: 0,
              },
            }
          : {}),
      } as Game;
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
        player_color: null,
        commander_name: null,
      };
      await firestoreService.addPlayer(player, gameId);

      trackEvent('create_game', { game_mode: gameMode });

      router.replace({
        pathname: '/(app)/lobby/[gameId]',
        params: { gameId, isHost: 'true' },
      });
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to create game.');
    }
    setIsCreating(false);
  };

  return (
    <ScrollView style={[styles.scrollView, isDesktop && styles.desktopScrollView]} contentContainerStyle={styles.container}>
      {/* Game Mode selector */}
      <View style={styles.section}>
        <Text style={styles.sectionHeader}>Game Mode</Text>
        <View style={styles.modeRow}>
          {GAME_MODES.map((mode) => (
            <TouchableOpacity
              key={mode.value}
              style={[styles.modeButton, gameMode === mode.value && styles.modeButtonSelected]}
              onPress={() => handleModeChange(mode.value)}
              accessibilityLabel={`${mode.label} game mode`}
              accessibilityRole="button"
              accessibilityState={{ selected: gameMode === mode.value }}
            >
              <Text
                style={[
                  styles.modeButtonText,
                  gameMode === mode.value && styles.modeButtonTextSelected,
                ]}
              >
                {mode.label}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>

      {/* Own deck toggle for planechase */}
      {hasPlanechase && (
        <View style={styles.toggleRow}>
          <Text style={styles.toggleLabel}>I have my own planar deck</Text>
          <Switch
            value={useOwnDeck}
            onValueChange={setUseOwnDeck}
            trackColor={{ false: colors.surface, true: colors.primary }}
            thumbColor={colors.text}
          />
        </View>
      )}

      {/* Starting life stepper */}
      <View style={styles.stepperRow}>
        <Text style={styles.stepperLabel}>Starting Life: {startingLife}</Text>
        <View style={styles.stepperButtons}>
          <TouchableOpacity
            onPress={() => setStartingLife(Math.max(20, startingLife - 5))}
            disabled={startingLife <= 20}
            accessibilityLabel="Decrease starting life"
            accessibilityRole="button"
          >
            <Text style={[styles.stepperBtn, startingLife <= 20 && styles.disabled]}>−</Text>
          </TouchableOpacity>
          <TouchableOpacity
            onPress={() => setStartingLife(Math.min(60, startingLife + 5))}
            disabled={startingLife >= 60}
            accessibilityLabel="Increase starting life"
            accessibilityRole="button"
          >
            <Text style={[styles.stepperBtn, startingLife >= 60 && styles.disabled]}>+</Text>
          </TouchableOpacity>
        </View>
      </View>

      {errorMessage && <ErrorBanner message={errorMessage} />}

      <TouchableOpacity
        style={[styles.createButton, isCreating && styles.buttonDisabled]}
        onPress={handleCreate}
        disabled={isCreating}
        accessibilityLabel={isCreating ? 'Creating game' : 'Create game'}
        accessibilityRole="button"
      >
        {isCreating ? (
          <View style={styles.buttonRow}>
            <ActivityIndicator size="small" color="#0d0b1a" />
            <Text style={styles.buttonText}>Creating...</Text>
          </View>
        ) : (
          <Text style={styles.buttonText}>Create Game</Text>
        )}
      </TouchableOpacity>

      <View style={{ flex: 1 }} />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scrollView: {
    flex: 1,
    backgroundColor: colors.background,
  },
  desktopScrollView: {
    maxWidth: contentMaxWidths.narrow,
    alignSelf: 'center',
    width: '100%',
  },
  container: {
    padding: spacing.lg,
    gap: spacing.xl,
  },
  section: {
    gap: spacing.sm,
  },
  sectionHeader: {
    color: colors.textSecondary,
    fontSize: fontSize.sm,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1.5,
  },
  modeRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  modeButton: {
    flex: 1,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.xs,
    backgroundColor: colors.surface,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
  },
  modeButtonSelected: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  modeButtonText: {
    color: colors.textSecondary,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },
  modeButtonTextSelected: {
    color: colors.background,
  },
  toggleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: 8,
    padding: 14,
    borderWidth: 1,
    borderColor: colors.border,
  },
  toggleLabel: {
    color: colors.text,
    fontSize: fontSize.lg,
  },
  stepperRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: 8,
    padding: 14,
    borderWidth: 1,
    borderColor: colors.border,
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
    color: '#0d0b1a',
    fontSize: 16,
    fontWeight: '700',
  },
});
