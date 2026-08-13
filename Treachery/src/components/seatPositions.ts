/**
 * Seat geometry for the desktop "round table" board.
 *
 * Coordinate space: fractions of the seating container's box — `x` grows to the
 * right, `y` grows DOWN (screen coordinates, so the numbers drop straight into
 * `left`/`top`). `{ x: 0.5, y: 0.5 }` is dead centre, i.e. the table itself.
 * Every position is the CENTRE of a tile, so a container places one with
 * `left: x * width - TILE_WIDTH / 2`, `top: y * height - TILE_HEIGHT / 2`.
 *
 * Nothing here touches React, the DOM, or the clock: same `count` in, same
 * array out.
 */

export interface SeatPosition {
  /** 0..1 fraction of container width, tile CENTER */
  x: number;
  /** 0..1 of height */
  y: number;
}

/**
 * Ellipse radii, also fractions of the container.
 *
 * Deliberately wider than tall. A tile is 200x150 (see TILE_WIDTH/TILE_HEIGHT
 * in PlayerTile), so neighbours collide sideways long before they collide
 * vertically — spreading seats out horizontally is what buys the clearance.
 * A circle in fraction space would do the opposite: on a board that is itself
 * much wider than tall it stacks every seat into a narrow column down the
 * middle and wastes the flanks.
 *
 * The leftover inset (0.5 - radius) is the margin a tile's own half-size has to
 * fit into. At a representative 1200x700 board that is 0.12*1200 = 144px of
 * room for a 100px half-width, and 0.16*700 = 112px for a 75px half-height —
 * comfortable at the sizes the board actually ships at.
 */
const RADIUS_X = 0.38;
const RADIUS_Y = 0.34;

const TAU = Math.PI * 2;

/** Four decimals is finer than any real pixel, and keeps the bottom seat exactly 0.5. */
function round(value: number): number {
  return Math.round(value * 10000) / 10000;
}

/**
 * Positions for `count` seats arranged around a table.
 * Index 0 is ALWAYS bottom-center (the local player's seat — the container
 * rotates the roster so "you" sit at the bottom, like a real table).
 * Remaining seats proceed clockwise.
 *
 * Clockwise is read off a clock face: from 6 o'clock the next mark is 7, so
 * seat 1 sits down-and-left of you and the ring comes back around the right.
 *
 * Even angular spacing is enough for every table size we support, and it lands
 * on an arrangement that looks chosen rather than generated at each count:
 *
 *   1  you alone at the bottom seat — the solo life-tracker case; keeping the
 *      invariant beats floating a lone tile into the middle of the table
 *   2  bottom and top, the two of you facing each other across the table
 *   3  an equilateral triangle: you at the bottom, both opponents flanking the top
 *   4  one seat per side: bottom, left, top, right
 *   5  a pentagon — a pair low on the flanks, a pair high
 *   6  a hexagon — a seat at bottom and top with a pair down each side
 *   7  a heptagon
 *   8  an octagon, and the tightest table Treachery supports. The closest pair
 *      is a flank neighbour (45 degrees vs 90 degrees): they overlap in x, and
 *      it is the ~168px between their centres on a 700px-tall board that keeps
 *      a 150px-tall tile clear — 18px to spare, and more on a taller board.
 *   9+ we keep distributing rather than throwing. Nine seats is not a legal
 *      Treachery game, but a stale roster or a future variant should degrade
 *      into a crowded ring, not crash the board. Past 8 the ring is tighter
 *      than a 200x150 tile likes, so a container that ever allows it should
 *      scale tiles down.
 */
export function seatPositions(count: number): SeatPosition[] {
  if (!Number.isFinite(count)) return [];
  const seats = Math.floor(count);
  if (seats < 1) return [];

  const positions: SeatPosition[] = [];
  for (let i = 0; i < seats; i += 1) {
    // angle 0 = bottom-center, growing clockwise on screen.
    const angle = (i / seats) * TAU;
    positions.push({
      x: round(0.5 - RADIUS_X * Math.sin(angle)),
      y: round(0.5 + RADIUS_Y * Math.cos(angle)),
    });
  }
  return positions;
}

/** Rotate `players` so the entry with the given id sits at index 0 (bottom seat). */
export function rotateToLocalFirst<T>(items: T[], isLocal: (item: T) => boolean): T[] {
  const index = items.findIndex((item) => isLocal(item));
  // No local player (spectator) or already first: hand back a copy either way,
  // so callers never get an alias of the array they passed in.
  if (index <= 0) return items.slice();
  return [...items.slice(index), ...items.slice(0, index)];
}
