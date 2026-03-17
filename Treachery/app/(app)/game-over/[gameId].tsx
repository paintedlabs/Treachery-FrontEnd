import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, FlatList } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '@/hooks/useAuth';
import { useGameBoard } from '@/hooks/useGameBoard';
import { LoadingScreen } from '@/components/LoadingScreen';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors, spacing, fonts } from '@/constants/theme';

export default function GameOverScreen() {
  const { gameId } = useLocalSearchParams<{ gameId: string }>();
  const router = useRouter();
  const { currentUserId } = useAuth();

  const { game, players, winningTeam, identityCard } = useGameBoard(gameId!, currentUserId);

  if (players.length === 0) {
    return <LoadingScreen message="Loading results..." />;
  }

  const isTreacheryMode =
    game?.game_mode === 'treachery' || game?.game_mode === 'treachery_planechase';

  const trophyColor = winningTeam ? ROLE_COLORS[winningTeam] : colors.text;

  return (
    <View style={styles.container}>
      <View style={styles.spacer} />

      {/* Winner announcement — treachery modes with a winning team */}
      {isTreacheryMode && winningTeam ? (
        <View style={styles.announcement}>
          <Ionicons name="trophy" size={56} color={trophyColor} />
          <Text style={styles.gameOverText}>Game Over</Text>

          {/* Ornate divider */}
          <View style={styles.ornateDivider}>
            <View style={styles.ornateLine} />
            <Text style={[styles.ornateDiamond, { color: trophyColor }]}>&#9670;</Text>
            <View style={styles.ornateLine} />
          </View>

          <View style={styles.winnerRow}>
            <View style={[styles.winnerDot, { backgroundColor: trophyColor }]} />
            <Text style={[styles.winnerText, { color: trophyColor }]}>
              {ROLE_DISPLAY_NAMES[winningTeam]} Wins!
            </Text>
          </View>
        </View>
      ) : (
        <View style={styles.announcement}>
          <Ionicons name="flag" size={56} color={colors.primary} />
          <Text style={styles.gameOverText}>Game Over</Text>

          <View style={styles.ornateDivider}>
            <View style={styles.ornateLine} />
            <Text style={[styles.ornateDiamond, { color: colors.primary }]}>&#9670;</Text>
            <View style={styles.ornateLine} />
          </View>

          <Text style={styles.sessionSummaryText}>
            Session ended with {players.length} player{players.length !== 1 ? 's' : ''}
          </Text>
        </View>
      )}

      {/* All players — show roles/cards only for treachery modes */}
      <View style={styles.playerList}>
        {players.map((player, index) => {
          if (isTreacheryMode) {
            const card = identityCard(player);
            const roleColor = player.role ? ROLE_COLORS[player.role] : colors.textSecondary;

            return (
              <View key={player.id}>
                <View style={styles.playerRow}>
                  <View style={[styles.accentBar, { backgroundColor: roleColor }]} />
                  <View style={[styles.roleDot, { backgroundColor: roleColor }]} />
                  <Text style={styles.playerName}>{player.display_name}</Text>
                  <View style={styles.playerRight}>
                    <Text style={[styles.roleText, { color: roleColor }]}>
                      {player.role ? ROLE_DISPLAY_NAMES[player.role] : 'Unknown'}
                    </Text>
                    {card && (
                      <Text style={styles.cardName}>{card.name}</Text>
                    )}
                  </View>
                  {player.is_eliminated && (
                    <Ionicons name="close-circle" size={14} color={colors.error} style={{ marginLeft: 4 }} />
                  )}
                </View>
                {index < players.length - 1 && <View style={styles.rowDivider} />}
              </View>
            );
          }

          // Non-treachery: simple player row with final life total
          return (
            <View key={player.id}>
              <View style={styles.playerRow}>
                <View style={[styles.accentBar, { backgroundColor: colors.primary }]} />
                <Text style={styles.playerName}>{player.display_name}</Text>
                <Text style={styles.lifeTotalText}>{player.life_total} life</Text>
              </View>
              {index < players.length - 1 && <View style={styles.rowDivider} />}
            </View>
          );
        })}
      </View>

      <View style={styles.spacer} />

      <TouchableOpacity
        style={styles.homeButton}
        onPress={() => router.replace('/(app)')}
        accessibilityLabel="Return to home"
        accessibilityRole="button"
      >
        <Text style={styles.homeButtonText}>Return to Home</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: spacing.lg,
  },
  spacer: {
    flex: 1,
  },
  announcement: {
    alignItems: 'center',
    gap: 8,
    marginBottom: spacing.xl,
  },
  gameOverText: {
    color: colors.text,
    fontSize: 32,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  ornateDivider: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    width: 180,
  },
  ornateLine: {
    flex: 1,
    height: 1,
    backgroundColor: colors.border,
  },
  ornateDiamond: {
    fontSize: 10,
  },
  winnerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  winnerDot: {
    width: 16,
    height: 16,
    borderRadius: 8,
  },
  winnerText: {
    fontSize: 24,
    fontWeight: '600',
    fontFamily: fonts.serif,
  },
  playerList: {
    backgroundColor: colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  playerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 12,
    gap: 8,
  },
  accentBar: {
    width: 3,
    alignSelf: 'stretch',
    borderRadius: 2,
  },
  roleDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
  },
  playerName: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '500',
    flex: 1,
  },
  playerRight: {
    alignItems: 'flex-end',
    gap: 2,
  },
  roleText: {
    fontSize: 14,
    fontWeight: '500',
  },
  cardName: {
    color: colors.textSecondary,
    fontSize: 12,
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
  rowDivider: {
    height: 1,
    backgroundColor: colors.divider,
    marginHorizontal: 12,
  },
  sessionSummaryText: {
    color: colors.textSecondary,
    fontSize: 16,
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
  lifeTotalText: {
    color: colors.textSecondary,
    fontSize: 14,
    fontWeight: '500',
  },
  homeButton: {
    backgroundColor: colors.primary,
    borderRadius: 8,
    padding: 14,
    alignItems: 'center',
    marginBottom: spacing.lg,
  },
  homeButtonText: {
    color: '#0d0b1a',
    fontSize: 16,
    fontWeight: '700',
  },
});
