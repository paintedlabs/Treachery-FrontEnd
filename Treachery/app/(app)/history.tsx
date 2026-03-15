import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  ActivityIndicator,
  RefreshControl,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '@/hooks/useAuth';
import { useGameHistory } from '@/hooks/useGameHistory';
import { ErrorBanner } from '@/components/ErrorBanner';
import { getCard } from '@/services/cardDatabase';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { Game, Player, Role } from '@/models/types';
import { colors, spacing } from '@/constants/theme';

export default function HistoryScreen() {
  const { currentUserId } = useAuth();
  const { games, gamePlayers, isLoading, errorMessage, refresh } =
    useGameHistory(currentUserId);

  if (isLoading) {
    return (
      <View style={styles.centerContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={styles.loadingText}>Loading game history...</Text>
      </View>
    );
  }

  if (games.length === 0) {
    return (
      <View style={styles.centerContainer}>
        <Ionicons name="time-outline" size={48} color={colors.textSecondary} />
        <Text style={styles.emptyTitle}>No games yet</Text>
        <Text style={styles.emptyText}>Finished games will appear here.</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <FlatList
        data={games}
        keyExtractor={(g) => g.id}
        renderItem={({ item: game }) => (
          <GameHistoryRow
            game={game}
            players={gamePlayers[game.id] ?? []}
            currentUserId={currentUserId}
          />
        )}
        refreshControl={
          <RefreshControl
            refreshing={isLoading}
            onRefresh={refresh}
            tintColor={colors.primary}
          />
        }
        contentContainerStyle={styles.listContent}
      />
      {errorMessage && <ErrorBanner message={errorMessage} />}
    </View>
  );
}

function GameHistoryRow({
  game,
  players,
  currentUserId,
}: {
  game: Game;
  players: Player[];
  currentUserId: string | null;
}) {
  const winningRole = game.winning_team as Role | null;
  const myPlayer = players.find((p) => p.user_id === currentUserId);
  const didWin = (() => {
    if (!myPlayer?.role || !winningRole) return false;
    if (winningRole === 'leader') {
      return myPlayer.role === 'leader' || myPlayer.role === 'guardian';
    }
    return myPlayer.role === winningRole;
  })();

  const formatDate = (timestamp: any) => {
    if (!timestamp) return '';
    const date = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
    return date.toLocaleDateString();
  };

  const formatTime = (timestamp: any) => {
    if (!timestamp) return '';
    const date = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  return (
    <View style={styles.gameCard}>
      {/* Header: date + result */}
      <View style={styles.gameHeader}>
        <View>
          <Text style={styles.dateText}>{formatDate(game.created_at)}</Text>
          <Text style={styles.timeText}>{formatTime(game.created_at)}</Text>
        </View>

        {winningRole && (
          <View style={styles.resultColumn}>
            <Text
              style={[styles.resultText, { color: didWin ? colors.success : colors.error }]}
            >
              {didWin ? 'Victory' : 'Defeat'}
            </Text>
            <View style={styles.winnerRow}>
              <View
                style={[styles.winnerDot, { backgroundColor: ROLE_COLORS[winningRole] }]}
              />
              <Text style={[styles.winnerText, { color: ROLE_COLORS[winningRole] }]}>
                {ROLE_DISPLAY_NAMES[winningRole]} Won
              </Text>
            </View>
          </View>
        )}
      </View>

      {/* Player grid */}
      {players.length > 0 && (
        <>
          <View style={styles.gameDivider} />
          <View style={styles.playerGrid}>
            {players.map((player) => {
              const roleColor = player.role
                ? ROLE_COLORS[player.role]
                : colors.textSecondary;
              return (
                <View key={player.id} style={styles.gridPlayer}>
                  <View style={[styles.gridDot, { backgroundColor: roleColor }]} />
                  <Text
                    style={[
                      styles.gridName,
                      player.user_id === currentUserId && styles.gridNameBold,
                    ]}
                    numberOfLines={1}
                  >
                    {player.display_name}
                  </Text>
                  {player.is_eliminated && (
                    <Ionicons name="close-circle" size={8} color={colors.error} />
                  )}
                </View>
              );
            })}
          </View>
        </>
      )}

      {/* My role */}
      {myPlayer?.role && (
        <View style={styles.myRoleRow}>
          <Text style={styles.myRoleLabel}>Your role:</Text>
          <Text
            style={[
              styles.myRoleValue,
              { color: ROLE_COLORS[myPlayer.role] },
            ]}
          >
            {ROLE_DISPLAY_NAMES[myPlayer.role]}
          </Text>
          {myPlayer.identity_card_id && (
            <Text style={styles.myCardName}>
              ({getCard(myPlayer.identity_card_id)?.name ?? ''})
            </Text>
          )}
        </View>
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
    gap: 12,
  },
  listContent: {
    padding: spacing.lg,
    gap: spacing.lg,
  },
  loadingText: {
    color: colors.textSecondary,
    fontSize: 14,
  },
  emptyTitle: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '600',
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: 14,
  },
  gameCard: {
    backgroundColor: colors.surface,
    borderRadius: 10,
    overflow: 'hidden',
    padding: 12,
    gap: 8,
  },
  gameHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  dateText: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '500',
  },
  timeText: {
    color: colors.textSecondary,
    fontSize: 12,
  },
  resultColumn: {
    alignItems: 'flex-end',
    gap: 2,
  },
  resultText: {
    fontSize: 14,
    fontWeight: 'bold',
  },
  winnerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  winnerDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  winnerText: {
    fontSize: 12,
  },
  gameDivider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.divider,
  },
  playerGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 4,
  },
  gridPlayer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    width: '48%',
  },
  gridDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  gridName: {
    color: colors.textSecondary,
    fontSize: 12,
    flex: 1,
  },
  gridNameBold: {
    color: colors.text,
    fontWeight: '600',
  },
  myRoleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  myRoleLabel: {
    color: colors.textSecondary,
    fontSize: 10,
  },
  myRoleValue: {
    fontSize: 10,
    fontWeight: '600',
  },
  myCardName: {
    color: colors.textSecondary,
    fontSize: 10,
  },
});
