import React from 'react';
import { Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { RoundTable } from '@/components/RoundTable';
import { PlayerTile } from '@/components/PlayerTile';
import { Player } from '@/models/types';
import { colors } from '@/constants/theme';

interface GameRoundTableProps {
  players: Player[];
  currentUserId: string | null;
  activePlayerId: string | null;
  isTreacheryActive: boolean;
  /** Eliminated viewer: no turn advancing, no reseating, inert life buttons. */
  isEliminatedSpectator: boolean;
  canSeeRole: (player: Player) => boolean;
  onAdjustLife: (playerId: string, amount: number) => void;
  onViewCard: (player: Player) => void;
  onRename: (name: string) => void;
  onColorChange: (color: string | null) => void;
  onReorder: (orderedPlayerIds: string[]) => void;
  onAdvanceTurn: () => void;
}

/**
 * Desktop game board: the Round Table of PlayerTiles with the Next Turn
 * control in the middle.
 */
export function GameRoundTable({
  players,
  currentUserId,
  activePlayerId,
  isTreacheryActive,
  isEliminatedSpectator,
  canSeeRole,
  onAdjustLife,
  onViewCard,
  onRename,
  onColorChange,
  onReorder,
  onAdvanceTurn,
}: GameRoundTableProps) {
  return (
    <RoundTable
      players={players}
      currentUserId={currentUserId}
      activePlayerId={activePlayerId}
      onReorder={onReorder}
      canReorder={!isEliminatedSpectator}
      center={
        <>
          <TouchableOpacity
            style={[styles.turnButton, isEliminatedSpectator && styles.buttonDisabled]}
            onPress={onAdvanceTurn}
            disabled={isEliminatedSpectator}
            accessibilityLabel="Next turn"
            accessibilityRole="button"
          >
            <Ionicons name="play-forward" size={16} color="#0d0b1a" />
            <Text style={styles.turnButtonText}>Next Turn</Text>
          </TouchableOpacity>
          {!isEliminatedSpectator && (
            <Text style={styles.tableHint}>Drag a player onto another seat to swap</Text>
          )}
        </>
      }
      renderTile={(item, state) => (
        <PlayerTile
          player={item}
          isCurrentUser={item.user_id === currentUserId}
          isActiveTurn={state.isActiveTurn}
          canSeeRole={isTreacheryActive ? canSeeRole(item) : false}
          isUnveiledOrLeader={item.is_unveiled || item.role === 'leader'}
          onAdjustLife={(amount) => onAdjustLife(item.id, amount)}
          onViewCard={() => onViewCard(item)}
          onRename={item.user_id === currentUserId ? onRename : undefined}
          onColorChange={item.user_id === currentUserId ? onColorChange : undefined}
          playerColor={item.player_color}
          isDragging={state.isDragging}
          isDropTarget={state.isDropTarget}
          isDisabled={isEliminatedSpectator}
        />
      )}
    />
  );
}

const styles = StyleSheet.create({
  turnButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: colors.primary,
    borderRadius: 8,
    paddingVertical: 10,
    paddingHorizontal: 18,
  },
  turnButtonText: {
    color: '#0d0b1a',
    fontSize: 15,
    fontWeight: '700',
  },
  tableHint: {
    color: colors.textTertiary,
    fontSize: 11,
    fontStyle: 'italic',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
});
