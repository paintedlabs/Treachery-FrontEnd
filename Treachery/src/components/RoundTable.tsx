import React, { useMemo, useRef, useState } from 'react';
import {
  Animated,
  LayoutChangeEvent,
  PanResponder,
  StyleSheet,
  View,
} from 'react-native';
import { Player } from '@/models/types';
import { TILE_HEIGHT, TILE_WIDTH } from '@/components/PlayerTile';
import { rotateToLocalFirst, seatPositions } from '@/components/seatPositions';
import { colors } from '@/constants/theme';

/**
 * The desktop "Round Table" board: player tiles arranged around a central
 * zone, draggable to match where people actually sit.
 *
 * Two things are worth knowing about how seating works here.
 *
 * The seat RING is shared — it lives in each player's `order_id` on the
 * server — but every client rotates it so that YOU are always in the bottom
 * seat (`rotateToLocalFirst`). That mirrors a physical table: everyone agrees
 * who is on whose left, while each person sees the table from their own
 * chair. Dragging therefore changes the shared ring, not just your view.
 *
 * Dragging uses PanResponder + Animated (core React Native, already the
 * codebase's animation approach in PlayerRow) rather than gesture-handler or
 * reanimated: it behaves consistently under react-native-web, where the
 * gesture libraries are fiddlier, and adds no new dependency.
 *
 * A drop SWAPS the dragged tile with the seat it lands on, rather than
 * splicing the ring. Swapping is what people expect when physically trading
 * chairs, and it keeps everyone else's position stable — a splice would shift
 * every downstream seat and make the board lurch.
 */

export interface RoundTableProps {
  /** All players, in shared seat order (order_id ascending). */
  players: Player[];
  currentUserId: string | null;
  /** Player doc id whose turn it is, or null. */
  activePlayerId: string | null;
  /**
   * Persist a new seating ring. Receives player doc ids in seat order,
   * expressed in SHARED order (rotation is undone before this is called).
   */
  onReorder: (orderedPlayerIds: string[]) => void;
  /** Renders one player's tile. `isDragging`/`isDropTarget` drive its visuals. */
  renderTile: (
    player: Player,
    state: { isActiveTurn: boolean; isDragging: boolean; isDropTarget: boolean },
  ) => React.ReactNode;
  /** Contents of the middle of the table (plane card, die, status). */
  center?: React.ReactNode;
}

export function RoundTable({
  players,
  currentUserId,
  activePlayerId,
  onReorder,
  renderTile,
  center,
}: RoundTableProps) {
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [dropTargetId, setDropTargetId] = useState<string | null>(null);

  // Rotated so the local player occupies seat 0 (bottom centre).
  const seated = useMemo(
    () => rotateToLocalFirst(players, (p) => p.user_id === currentUserId),
    [players, currentUserId],
  );
  const positions = useMemo(() => seatPositions(seated.length), [seated.length]);

  const onLayout = (e: LayoutChangeEvent) => {
    const { width, height } = e.nativeEvent.layout;
    setSize((prev) => (prev.width === width && prev.height === height ? prev : { width, height }));
  };

  /** Absolute top-left pixel position of a seat, given its centre fraction. */
  const seatOrigin = (index: number) => {
    const pos = positions[index] ?? { x: 0.5, y: 0.5 };
    return {
      left: pos.x * size.width - TILE_WIDTH / 2,
      top: pos.y * size.height - TILE_HEIGHT / 2,
    };
  };

  return (
    <View style={styles.container} onLayout={onLayout}>
      {/* The table itself — a felt ellipse the tiles sit around. */}
      <View style={styles.tableSurface} pointerEvents="box-none">
        <View style={styles.tableCenter} pointerEvents="box-none">
          {center}
        </View>
      </View>

      {size.width > 0 &&
        seated.map((player, index) => (
          <DraggableSeat
            key={player.id}
            index={index}
            origin={seatOrigin(index)}
            isDragging={draggingId === player.id}
            onDragStart={() => {
              setDraggingId(player.id);
              setDropTargetId(null);
            }}
            onDragMove={(dx, dy) => {
              // Which seat centre is the tile's centre currently nearest?
              const from = seatOrigin(index);
              const cx = from.left + dx + TILE_WIDTH / 2;
              const cy = from.top + dy + TILE_HEIGHT / 2;
              // Plain loop rather than forEach: assignments inside a closure
              // defeat TypeScript's narrowing of `nearestId` below.
              let nearestId: string | null = null;
              let nearestDist = Infinity;
              for (let otherIndex = 0; otherIndex < seated.length; otherIndex++) {
                if (otherIndex === index) continue;
                const o = seatOrigin(otherIndex);
                const dist = Math.hypot(
                  cx - (o.left + TILE_WIDTH / 2),
                  cy - (o.top + TILE_HEIGHT / 2),
                );
                if (dist < nearestDist) {
                  nearestDist = dist;
                  nearestId = seated[otherIndex].id;
                }
              }
              // Only treat it as a drop when meaningfully inside the seat —
              // otherwise every tiny drag would highlight a neighbour.
              setDropTargetId(nearestDist < TILE_WIDTH * 0.6 ? nearestId : null);
            }}
            onDragEnd={() => {
              const targetId = dropTargetId;
              setDraggingId(null);
              setDropTargetId(null);
              if (!targetId || targetId === player.id) return;

              // Swap the two seats in the ROTATED view...
              const next = seated.slice();
              const a = next.findIndex((p) => p.id === player.id);
              const b = next.findIndex((p) => p.id === targetId);
              if (a < 0 || b < 0) return;
              [next[a], next[b]] = [next[b], next[a]];

              // ...then undo the rotation so the server receives the shared
              // ring. Rotating by the local player's original offset keeps
              // everyone else's absolute seats intact.
              const offset = players.findIndex((p) => p.user_id === currentUserId);
              const shift = offset > 0 ? offset : 0;
              const shared = next.map(
                (_, i) => next[(i - shift + next.length * 2) % next.length],
              );
              onReorder(shared.map((p) => p.id));
            }}
          >
            {renderTile(player, {
              isActiveTurn: player.id === activePlayerId,
              isDragging: draggingId === player.id,
              isDropTarget: dropTargetId === player.id,
            })}
          </DraggableSeat>
        ))}
    </View>
  );
}

interface DraggableSeatProps {
  index: number;
  origin: { left: number; top: number };
  isDragging: boolean;
  onDragStart: () => void;
  onDragMove: (dx: number, dy: number) => void;
  onDragEnd: () => void;
  children: React.ReactNode;
}

function DraggableSeat({
  origin,
  isDragging,
  onDragStart,
  onDragMove,
  onDragEnd,
  children,
}: DraggableSeatProps) {
  const pan = useRef(new Animated.ValueXY({ x: 0, y: 0 })).current;

  const responder = useRef(
    PanResponder.create({
      // Don't capture the touch on press — the tile's own +/- buttons must
      // still work. Only claim the gesture once it's clearly a drag.
      onMoveShouldSetPanResponder: (_evt, gesture) =>
        Math.abs(gesture.dx) > 6 || Math.abs(gesture.dy) > 6,
      onPanResponderGrant: () => {
        pan.setValue({ x: 0, y: 0 });
        onDragStart();
      },
      onPanResponderMove: (evt, gesture) => {
        pan.setValue({ x: gesture.dx, y: gesture.dy });
        onDragMove(gesture.dx, gesture.dy);
      },
      onPanResponderRelease: () => {
        onDragEnd();
        // Spring home: the tile's real position comes from the seat ring once
        // the server round-trips, so the drag offset must always reset.
        Animated.spring(pan, {
          toValue: { x: 0, y: 0 },
          useNativeDriver: false,
          friction: 7,
        }).start();
      },
      onPanResponderTerminate: () => {
        onDragEnd();
        pan.setValue({ x: 0, y: 0 });
      },
    }),
  ).current;

  return (
    <Animated.View
      {...responder.panHandlers}
      style={[
        styles.seat,
        origin,
        { transform: pan.getTranslateTransform() },
        isDragging && styles.seatDragging,
      ]}
    >
      {children}
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    position: 'relative',
    minHeight: 560,
  },
  tableSurface: {
    ...StyleSheet.absoluteFillObject,
    margin: 90,
    borderRadius: 9999,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  tableCenter: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
    padding: 20,
  },
  seat: {
    position: 'absolute',
    width: TILE_WIDTH,
    height: TILE_HEIGHT,
  },
  seatDragging: {
    // Lift the dragged tile above its neighbours.
    zIndex: 10,
  },
});
