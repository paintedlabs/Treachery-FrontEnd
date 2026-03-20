import React, { useEffect, useState, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  FlatList,
  ActivityIndicator,
  Alert,
  Share,
  Platform,
  Animated,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as Clipboard from 'expo-clipboard';
import { useAuth } from '@/hooks/useAuth';
import { useLobby } from '@/hooks/useLobby';
import { ErrorBanner } from '@/components/ErrorBanner';
import { LoadingScreen } from '@/components/LoadingScreen';
import { ConnectionBanner } from '@/components/ConnectionBanner';
import { Player } from '@/models/types';
import { colors, spacing, fonts, PLAYER_COLORS } from '@/constants/theme';

const MODE_DISPLAY: Record<string, string> = {
  treachery: 'Treachery',
  planechase: 'Planechase',
  treachery_planechase: 'Treachery + Planechase',
  none: 'Life Tracker',
};

function LobbyPlayerRow({
  item,
  isCurrentUser,
  isHostPlayer,
  onColorChange,
  onCommanderNameSubmit,
}: {
  item: Player;
  isCurrentUser: boolean;
  isHostPlayer: boolean;
  onColorChange?: (color: string | null) => void;
  onCommanderNameSubmit?: (name: string | null) => void;
}) {
  const [showColorPicker, setShowColorPicker] = useState(false);
  const [commanderDraft, setCommanderDraft] = useState(item.commander_name ?? '');
  const pickerHeight = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(pickerHeight, {
      toValue: showColorPicker ? 48 : 0,
      duration: 200,
      useNativeDriver: false,
    }).start();
  }, [showColorPicker, pickerHeight]);

  const handleColorSelect = (hex: string) => {
    onColorChange?.(hex);
    setShowColorPicker(false);
  };

  const handleClearColor = () => {
    onColorChange?.(null);
    setShowColorPicker(false);
  };

  const handleCommanderBlur = () => {
    const trimmed = commanderDraft.trim();
    if (trimmed !== (item.commander_name ?? '')) {
      onCommanderNameSubmit?.(trimmed || null);
    }
  };

  return (
    <View>
      <View style={styles.playerRow}>
        {/* Left accent bar for player color */}
        {item.player_color && (
          <View style={[styles.accentBar, { backgroundColor: item.player_color }]} />
        )}

        {/* Color circle for current user, or player icon for others */}
        {isCurrentUser && onColorChange ? (
          <TouchableOpacity
            onPress={() => setShowColorPicker(!showColorPicker)}
            accessibilityLabel="Choose player color"
            accessibilityRole="button"
          >
            <View
              style={[
                styles.playerIcon,
                item.player_color
                  ? { backgroundColor: item.player_color, borderColor: item.player_color }
                  : {},
              ]}
            >
              <Ionicons
                name="color-palette"
                size={14}
                color={item.player_color ? '#fff' : colors.textSecondary}
              />
            </View>
          </TouchableOpacity>
        ) : (
          <View
            style={[
              styles.playerIcon,
              item.player_color
                ? { backgroundColor: item.player_color, borderColor: item.player_color }
                : {},
            ]}
          >
            <Ionicons
              name="person"
              size={14}
              color={item.player_color ? '#fff' : colors.textSecondary}
            />
          </View>
        )}

        <View style={styles.playerInfo}>
          <Text style={[styles.playerName, isHostPlayer && styles.bold]}>{item.display_name}</Text>
          {/* Commander name display for non-current users */}
          {!isCurrentUser && item.commander_name ? (
            <Text style={styles.commanderNameDisplay}>{item.commander_name}</Text>
          ) : null}
          {/* Commander name input for current user */}
          {isCurrentUser && onCommanderNameSubmit && (
            <TextInput
              style={styles.commanderInput}
              placeholder="Commander name..."
              placeholderTextColor={colors.textTertiary}
              value={commanderDraft}
              onChangeText={setCommanderDraft}
              onBlur={handleCommanderBlur}
              onSubmitEditing={handleCommanderBlur}
              returnKeyType="done"
              maxLength={40}
            />
          )}
        </View>

        {isHostPlayer && (
          <View style={styles.hostBadge}>
            <Text style={styles.hostBadgeText}>Host</Text>
          </View>
        )}
      </View>

      {/* Color picker strip — animated */}
      {isCurrentUser && onColorChange && (
        <Animated.View style={[styles.colorPickerContainer, { height: pickerHeight }]}>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.colorPickerContent}
          >
            {PLAYER_COLORS.map((c) => (
              <TouchableOpacity
                key={c.hex}
                onPress={() => handleColorSelect(c.hex)}
                accessibilityLabel={`Select ${c.name} color`}
                accessibilityRole="button"
              >
                <View
                  style={[
                    styles.colorOption,
                    { backgroundColor: c.hex },
                    item.player_color === c.hex && styles.colorOptionSelected,
                  ]}
                />
              </TouchableOpacity>
            ))}
            <TouchableOpacity
              onPress={handleClearColor}
              accessibilityLabel="Clear color"
              accessibilityRole="button"
            >
              <View style={styles.colorClear}>
                <Ionicons name="close" size={14} color={colors.textSecondary} />
              </View>
            </TouchableOpacity>
          </ScrollView>
        </Animated.View>
      )}
    </View>
  );
}

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
    minPlayers,
    startGame,
    leaveGame,
    updatePlayerColor,
    updateCommanderName,
  } = useLobby(gameId!, isHost, currentUserId);

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

  const [isLeaving, setIsLeaving] = useState(false);

  const doLeave = async () => {
    setIsLeaving(true);
    if (currentUserId) {
      await leaveGame(currentUserId);
    }
    router.replace('/(app)');
  };

  const handleLeave = () => {
    if (Platform.OS === 'web') {
      if (window.confirm('Are you sure you want to leave?')) {
        doLeave();
      }
    } else {
      Alert.alert('Leave Game', 'Are you sure you want to leave?', [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Leave',
          style: 'destructive',
          onPress: doLeave,
        },
      ]);
    }
  };

  if (!game && !errorMessage && !isGameDisbanded) {
    return <LoadingScreen message="Loading lobby..." />;
  }

  if (isGameDisbanded) {
    return (
      <View style={styles.centerContainer}>
        <Ionicons name="close-circle" size={48} color={colors.error} />
        <Text style={styles.disbandedTitle}>Game Disbanded</Text>
        <Text style={styles.disbandedText}>The host has left and the game was closed.</Text>
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

  const currentPlayerColor = players.find((p) => p.user_id === currentUserId)?.player_color;

  return (
    <View style={styles.container}>
      {/* Player color background tint */}
      {currentPlayerColor && (
        <View
          style={[StyleSheet.absoluteFill, { backgroundColor: currentPlayerColor, opacity: 0.15 }]}
          pointerEvents="none"
        />
      )}

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
            {game.game_mode && (
              <View style={styles.modeBadge}>
                <Text style={styles.modeBadgeText}>
                  {MODE_DISPLAY[game.game_mode] ?? game.game_mode}
                </Text>
              </View>
            )}
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
          renderItem={({ item }) => {
            const isCurrent = item.user_id === currentUserId;
            return (
              <LobbyPlayerRow
                item={item}
                isCurrentUser={isCurrent}
                isHostPlayer={item.user_id === game?.host_id}
                onColorChange={isCurrent ? updatePlayerColor : undefined}
                onCommanderNameSubmit={isCurrent ? updateCommanderName : undefined}
              />
            );
          }}
          style={styles.list}
          keyboardShouldPersistTaps="handled"
        />
      )}

      {!isHost && (
        <View style={styles.waitingRow}>
          <ActivityIndicator size="small" color={colors.primary} />
          <Text style={styles.waitingForHost}>Waiting for host to start the game...</Text>
        </View>
      )}

      {errorMessage && <ErrorBanner message={errorMessage} />}

      {/* Bottom buttons */}
      <View style={styles.bottomButtons}>
        {isHost && (
          <>
            <TouchableOpacity
              style={[
                styles.primaryButton,
                (!canStartGame || isStartingGame) && styles.buttonDisabled,
              ]}
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

            {!canStartGame && players.length < minPlayers && (
              <Text style={styles.minPlayersText}>Need at least {minPlayers} players to start</Text>
            )}
          </>
        )}

        <TouchableOpacity
          style={styles.leaveButton}
          onPress={handleLeave}
          disabled={isLeaving}
          accessibilityLabel="Leave game"
          accessibilityRole="button"
        >
          {isLeaving ? (
            <View style={styles.buttonRow}>
              <ActivityIndicator size="small" color={colors.destructive} />
              <Text style={styles.leaveText}>Leaving...</Text>
            </View>
          ) : (
            <Text style={styles.leaveText}>Leave Game</Text>
          )}
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
  modeBadge: {
    backgroundColor: 'rgba(201, 168, 76, 0.15)',
    borderWidth: 1,
    borderColor: 'rgba(201, 168, 76, 0.3)',
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderRadius: 10,
    marginTop: 8,
  },
  modeBadgeText: {
    color: colors.primary,
    fontSize: 12,
    fontWeight: '600',
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
  accentBar: {
    width: 3,
    alignSelf: 'stretch',
    borderRadius: 2,
    marginRight: 10,
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
  playerInfo: {
    flex: 1,
    gap: 2,
  },
  playerName: {
    color: colors.text,
    fontSize: 16,
  },
  bold: {
    fontWeight: '600',
  },
  commanderNameDisplay: {
    fontSize: 12,
    color: colors.textSecondary,
    fontStyle: 'italic',
  },
  commanderInput: {
    fontSize: 12,
    color: colors.textSecondary,
    fontStyle: 'italic',
    paddingVertical: 2,
    paddingHorizontal: 0,
    margin: 0,
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
  colorPickerContainer: {
    overflow: 'hidden',
    backgroundColor: colors.background,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  colorPickerContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  colorOption: {
    width: 28,
    height: 28,
    borderRadius: 14,
  },
  colorOptionSelected: {
    borderWidth: 2.5,
    borderColor: colors.text,
  },
  colorClear: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
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
