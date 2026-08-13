import React, { useMemo, useRef, useState } from 'react';
import { Animated, LayoutChangeEvent, StyleSheet, View } from 'react-native';
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
 * Dragging uses the Pointer Events API (see DraggableSeat below for why
 * PanResponder does not work here) with core Animated for the transform —
 * no new dependency.
 *
 * A drop SWAPS the dragged tile with the seat it lands on, rather than
 * splicing the ring. Swapping is what people expect when physically trading
 * chairs, and it keeps everyone else's position stable — a splice would shift
 * every downstream seat and make the board lurch.
 */

/** Breathing room between a tile edge and the board edge. */
const SEAT_PADDING = 8;

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
  /** When false, seats stay put (eliminated spectators cannot restack the table). */
  canReorder?: boolean;
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
  canReorder = true,
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

  // seatPositions works in fractions of the container, but tiles are a fixed
  // pixel size — so a fraction that fits a wide board overflows a narrow one
  // (the desktop board is a ~560px column once the identity sidebar takes its
  // half). Rescale the ring to the space actually available after reserving
  // room for a tile, so the layout is correct at any container size.
  //
  // The scale is derived from the positions themselves rather than from the
  // ellipse constants, so this stays correct if that geometry ever changes.
  const extent = useMemo(() => {
    let dx = 0;
    let dy = 0;
    for (const p of positions) {
      dx = Math.max(dx, Math.abs(p.x - 0.5));
      dy = Math.max(dy, Math.abs(p.y - 0.5));
    }
    return { dx, dy };
  }, [positions]);

  /** Absolute top-left pixel position of a seat, given its centre fraction. */
  const seatOrigin = (index: number) => {
    const pos = positions[index] ?? { x: 0.5, y: 0.5 };
    const availX = Math.max(0, (size.width - TILE_WIDTH) / 2 - SEAT_PADDING);
    const availY = Math.max(0, (size.height - TILE_HEIGHT) / 2 - SEAT_PADDING);
    // extent 0 means a single seat dead centre — no offset to scale.
    const offsetX = extent.dx > 0 ? ((pos.x - 0.5) / extent.dx) * availX : 0;
    const offsetY = extent.dy > 0 ? ((pos.y - 0.5) / extent.dy) * availY : 0;
    return {
      left: size.width / 2 + offsetX - TILE_WIDTH / 2,
      top: size.height / 2 + offsetY - TILE_HEIGHT / 2,
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
        seated.map((player, index) => {
          const tile = renderTile(player, {
            isActiveTurn: player.id === activePlayerId,
            isDragging: draggingId === player.id,
            isDropTarget: dropTargetId === player.id,
          });
          if (!canReorder) {
            return (
              <View key={player.id} style={[styles.seat, seatOrigin(index)]}>
                {tile}
              </View>
            );
          }
          return (
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
            {tile}
          </DraggableSeat>
          );
        })}
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

/**
 * Pointer events rather than PanResponder.
 *
 * PanResponder never grants on react-native-web here: its gestureState is
 * synthesised from a touch history that reports zero deltas for mouse input,
 * and even an unconditional `onMoveShouldSetPanResponder` failed to take the
 * responder for real (CDP-dispatched) mouse drags. The Pointer Events API is
 * forwarded straight to the DOM by react-native-web and is supported by React
 * Native itself since 0.71, so this is the portable choice rather than a
 * web-only escape hatch.
 *
 * `setPointerCapture` keeps the gesture attached to this tile once it starts,
 * so dragging across a neighbouring tile (or off the board) still tracks and
 * still delivers the release.
 */
function DraggableSeat({
  origin,
  isDragging,
  onDragStart,
  onDragMove,
  onDragEnd,
  children,
}: DraggableSeatProps) {
  const pan = useRef(new Animated.ValueXY({ x: 0, y: 0 })).current;
  const start = useRef<{ x: number; y: number } | null>(null);
  const moved = useRef(false);

  const handlePointerDown = (e: PointerEventLike) => {
    // Record the origin but do NOT capture the pointer yet. Capturing here
    // redirects every later pointer event to this tile, so the +/- buttons
    // inside it never receive their pointerup and never fire a click.
    // Capture is taken below, only once the gesture is confirmed a drag.
    start.current = { x: e.nativeEvent.clientX, y: e.nativeEvent.clientY };
    moved.current = false;
  };

  const handlePointerMove = (e: PointerEventLike) => {
    if (!start.current) return;
    const dx = e.nativeEvent.clientX - start.current.x;
    const dy = e.nativeEvent.clientY - start.current.y;
    // A few pixels of slop so a click on +/- isn't read as a drag.
    if (!moved.current && Math.abs(dx) < 6 && Math.abs(dy) < 6) return;
    if (!moved.current) {
      moved.current = true;
      // Now that this is definitely a drag, capture so it keeps tracking
      // across neighbouring tiles and off the board.
      const target = e.currentTarget as unknown as {
        setPointerCapture?: (id: number) => void;
      };
      target?.setPointerCapture?.(e.nativeEvent.pointerId);
      onDragStart();
    }
    pan.setValue({ x: dx, y: dy });
    onDragMove(dx, dy);
  };

  const endDrag = (e: PointerEventLike) => {
    const target = e.currentTarget as unknown as {
      releasePointerCapture?: (id: number) => void;
    };
    target?.releasePointerCapture?.(e.nativeEvent.pointerId);
    start.current = null;
    if (!moved.current) return; // a tap, not a drag — leave it to the buttons
    moved.current = false;
    onDragEnd();
    // Spring home: the tile's real position comes from the seat ring once the
    // server round-trips, so the drag offset must always reset.
    Animated.spring(pan, {
      toValue: { x: 0, y: 0 },
      useNativeDriver: false,
      friction: 7,
    }).start();
  };

  return (
    <Animated.View
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
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

/** Minimal shape of the pointer events react-native-web forwards. */
interface PointerEventLike {
  currentTarget: unknown;
  nativeEvent: { clientX: number; clientY: number; pointerId: number };
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
