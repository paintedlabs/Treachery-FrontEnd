import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  FlatList,
  Alert,
  Platform,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '@/hooks/useAuth';
import { useGameBoard } from '@/hooks/useGameBoard';
import { IdentityCardHeader } from '@/components/IdentityCardHeader';
import { IdentityCardDetail } from '@/components/IdentityCardDetail';
import { PlayerRow } from '@/components/PlayerRow';
import { ErrorBanner } from '@/components/ErrorBanner';
import { LoadingScreen } from '@/components/LoadingScreen';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES, ROLE_WIN_CONDITIONS } from '@/constants/roles';
import { Player } from '@/models/types';
import { colors, spacing } from '@/constants/theme';

export default function GameBoardScreen() {
  const { gameId } = useLocalSearchParams<{ gameId: string }>();
  const router = useRouter();
  const { currentUserId } = useAuth();

  const {
    game,
    players,
    errorMessage,
    isGameUnavailable,
    isGameFinished,
    currentPlayer,
    currentIdentityCard,
    adjustLife,
    unveilCurrentPlayer,
    eliminateAndLeave,
    canSeeRole,
    identityCard,
  } = useGameBoard(gameId!, currentUserId);

  const [showCardDetail, setShowCardDetail] = useState(false);
  const [inspectedPlayer, setInspectedPlayer] = useState<Player | null>(null);
  const [showUnveilConfirm, setShowUnveilConfirm] = useState(false);

  // Navigate to game over when finished
  useEffect(() => {
    if (isGameFinished) {
      router.replace({
        pathname: '/(app)/game-over/[gameId]',
        params: { gameId: gameId! },
      });
    }
  }, [isGameFinished, gameId, router]);

  // Handle game unavailable
  useEffect(() => {
    if (isGameUnavailable) {
      Alert.alert('Game Unavailable', 'This game is no longer available.', [
        { text: 'OK', onPress: () => router.replace('/(app)') },
      ]);
    }
  }, [isGameUnavailable, router]);

  const handleForfeit = () => {
    if (Platform.OS === 'web') {
      const confirmed = window.confirm('Forfeit Game?\n\nYou will be eliminated from the game. This cannot be undone.');
      if (confirmed) {
        eliminateAndLeave().then(() => router.replace('/(app)'));
      }
    } else {
      Alert.alert(
        'Forfeit Game?',
        'You will be eliminated from the game. This cannot be undone.',
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Forfeit',
            style: 'destructive',
            onPress: async () => {
              await eliminateAndLeave();
              router.replace('/(app)');
            },
          },
        ]
      );
    }
  };

  const handleUnveil = () => {
    const roleName = currentPlayer?.role ? ROLE_DISPLAY_NAMES[currentPlayer.role] : '';
    const cardName = currentIdentityCard?.name ?? '';
    if (Platform.OS === 'web') {
      const confirmed = window.confirm(
        `Unveil your identity?\n\nThis will reveal your role (${roleName}) and card (${cardName}) to all players. This cannot be undone.`
      );
      if (confirmed) unveilCurrentPlayer();
    } else {
      Alert.alert(
        'Unveil your identity?',
        `This will reveal your role (${roleName}) and card (${cardName}) to all players. This cannot be undone.`,
        [
          { text: 'Cancel', style: 'cancel' },
          { text: 'Unveil', onPress: () => unveilCurrentPlayer() },
        ]
      );
    }
  };

  if (isGameUnavailable) {
    return (
      <View style={styles.centerContainer}>
        <Ionicons name="wifi" size={48} color={colors.warning} />
        <Text style={styles.unavailableTitle}>Game Unavailable</Text>
        <Text style={styles.unavailableText}>
          This game is no longer available.
        </Text>
        <TouchableOpacity
          style={styles.primaryButton}
          onPress={() => router.replace('/(app)')}
        >
          <Text style={styles.buttonText}>Return to Home</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (players.length === 0) {
    return <LoadingScreen message="Loading game..." />;
  }

  const inspectedCard = inspectedPlayer ? identityCard(inspectedPlayer) : undefined;

  return (
    <View style={styles.container}>
      {/* Identity card header */}
      {currentIdentityCard && currentPlayer && (
        <IdentityCardHeader
          card={currentIdentityCard}
          player={currentPlayer}
          onPress={() => setShowCardDetail(true)}
        />
      )}

      <View style={styles.divider} />

      {/* Player list */}
      <FlatList
        data={players}
        keyExtractor={(p) => p.id}
        renderItem={({ item }) => (
          <PlayerRow
            player={item}
            isCurrentUser={item.user_id === currentUserId}
            canSeeRole={canSeeRole(item)}
            isUnveiledOrLeader={item.is_unveiled || item.role === 'leader'}
            onAdjustLife={(amount) => adjustLife(item.id, amount)}
            onViewCard={() => setInspectedPlayer(item)}
          />
        )}
        style={styles.list}
      />

      {errorMessage && <ErrorBanner message={errorMessage} />}

      {/* Action bar */}
      <View style={styles.actionBar}>
        {currentPlayer &&
          !currentPlayer.is_unveiled &&
          !currentPlayer.is_eliminated &&
          currentPlayer.role !== 'leader' && (
            <TouchableOpacity
              style={[
                styles.unveilButton,
                {
                  backgroundColor: currentPlayer.role
                    ? ROLE_COLORS[currentPlayer.role]
                    : colors.primary,
                },
              ]}
              onPress={handleUnveil}
            >
              <Text style={styles.buttonText}>Unveil Identity</Text>
            </TouchableOpacity>
          )}

        {currentPlayer?.role && (
          <Text style={styles.winConditionText}>
            {ROLE_WIN_CONDITIONS[currentPlayer.role]}
          </Text>
        )}
      </View>

      {/* Forfeit button */}
      {currentPlayer && !currentPlayer.is_eliminated && (
        <TouchableOpacity style={styles.forfeitButton} onPress={handleForfeit}>
          <Ionicons name="flag" size={16} color={colors.warning} />
          <Text style={styles.forfeitText}>Forfeit</Text>
        </TouchableOpacity>
      )}

      {/* Card detail modal */}
      {currentIdentityCard && currentPlayer && (
        <IdentityCardDetail
          card={currentIdentityCard}
          player={currentPlayer}
          visible={showCardDetail}
          onClose={() => setShowCardDetail(false)}
        />
      )}

      {/* Inspected player card modal */}
      {inspectedCard && inspectedPlayer && (
        <IdentityCardDetail
          card={inspectedCard}
          player={inspectedPlayer}
          visible={!!inspectedPlayer}
          onClose={() => setInspectedPlayer(null)}
        />
      )}
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
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.divider,
  },
  list: {
    flex: 1,
  },
  actionBar: {
    padding: spacing.lg,
    alignItems: 'center',
    gap: 12,
  },
  unveilButton: {
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    width: '100%',
  },
  primaryButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    minWidth: 200,
  },
  buttonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
  },
  winConditionText: {
    color: colors.textSecondary,
    fontSize: 11,
    textAlign: 'center',
  },
  forfeitButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingBottom: spacing.lg,
  },
  forfeitText: {
    color: colors.warning,
    fontSize: 14,
  },
  unavailableTitle: {
    color: colors.text,
    fontSize: 20,
    fontWeight: 'bold',
  },
  unavailableText: {
    color: colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
  },
});
