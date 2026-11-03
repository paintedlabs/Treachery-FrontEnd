import React from 'react';
import { FlatList, StyleSheet } from 'react-native';
import { PlayerRow } from '@/components/PlayerRow';
import { Player } from '@/models/types';

interface GamePlayerListProps {
  players: Player[];
  currentUserId: string | null;
  isTreacheryActive: boolean;
  /** Eliminated viewer: life buttons stay visible but do nothing. */
  isEliminatedSpectator: boolean;
  canSeeRole: (player: Player) => boolean;
  onAdjustLife: (playerId: string, amount: number) => void;
  onViewCard: (player: Player) => void;
  onRename: (name: string) => void;
  onColorChange: (color: string | null) => void;
}

/** Mobile game board: the vertical roster of PlayerRows. */
export function GamePlayerList({
  players,
  currentUserId,
  isTreacheryActive,
  isEliminatedSpectator,
  canSeeRole,
  onAdjustLife,
  onViewCard,
  onRename,
  onColorChange,
}: GamePlayerListProps) {
  return (
    <FlatList
      data={players}
      keyExtractor={(p) => p.id}
      renderItem={({ item }) => (
        <PlayerRow
          player={item}
          isCurrentUser={item.user_id === currentUserId}
          canSeeRole={isTreacheryActive ? canSeeRole(item) : false}
          isUnveiledOrLeader={item.is_unveiled || item.role === 'leader'}
          onAdjustLife={(amount) => onAdjustLife(item.id, amount)}
          onViewCard={() => onViewCard(item)}
          isDisabled={isEliminatedSpectator}
          onColorChange={item.user_id === currentUserId ? onColorChange : undefined}
          playerColor={item.player_color}
          onRename={item.user_id === currentUserId ? onRename : undefined}
        />
      )}
      style={styles.list}
    />
  );
}

const styles = StyleSheet.create({
  list: {
    flex: 1,
  },
});
