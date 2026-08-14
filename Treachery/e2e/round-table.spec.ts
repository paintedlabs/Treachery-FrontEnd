import { test, expect, Page } from '@playwright/test';
import { fetchGameDoc, fetchPlayerDocs, setupSeededGame } from './helpers';

/**
 * The desktop Round Table board: seat ring, drag-to-reorder, and the turn
 * marker.
 *
 * These run at a desktop viewport because the board only renders above the
 * desktop breakpoint — below it the game screen keeps the mobile PlayerRow
 * list, which the rest of the suite covers.
 */

test.use({ viewport: { width: 1440, height: 900 } });

/** Player doc ids in shared seat order (order_id ascending). */
async function seatOrder(page: Page, gameId: string): Promise<string[]> {
  const docs = await fetchPlayerDocs(page, gameId);
  return docs
    .slice()
    .sort((a, b) => (a.order_id ?? 0) - (b.order_id ?? 0))
    .map((d) => d.id);
}

/** Centre of a player's tile on the board. */
async function tileCentre(page: Page, name: string) {
  const tile = page.getByText(name, { exact: true }).first();
  await expect(tile).toBeVisible();
  const box = await tile.boundingBox();
  if (!box) throw new Error(`No bounding box for ${name}`);
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

test('the board seats every player and marks whose turn it is', async ({ browser }) => {
  const { players, gameId, host } = await setupSeededGame(browser, [
    'leader',
    'assassin',
    'assassin',
    'traitor',
  ]);

  // Every player has a tile.
  for (const p of players) {
    await expect(host.page.getByText(p.name, { exact: true }).first()).toBeVisible();
  }

  // startGame seeds the turn onto the first seat, and the board shows it.
  const seats = await seatOrder(host.page, gameId);
  const game = await fetchGameDoc(host.page, gameId);
  expect(game?.active_player_id).toBe(seats[0]);
  await expect(host.page.getByText('Turn', { exact: false }).first()).toBeVisible();

  // Advancing moves the marker to the next seat, for everyone.
  await host.page.getByRole('button', { name: 'Next turn' }).click();
  await expect
    .poll(async () => (await fetchGameDoc(host.page, gameId))?.active_player_id, {
      timeout: 10_000,
    })
    .toBe(seats[1]);
});

test('dragging a player onto another seat swaps them for the whole table', async ({
  browser,
}) => {
  const { players, gameId, host } = await setupSeededGame(browser, [
    'leader',
    'assassin',
    'assassin',
    'traitor',
  ]);
  const observer = players[1];

  const before = await seatOrder(host.page, gameId);
  expect(before).toHaveLength(4);

  // Drag the tile of one opponent onto another opponent's seat. Real mouse
  // input with intermediate moves — a single jump does not produce the
  // pointermove stream a drag needs.
  const from = await tileCentre(host.page, players[2].name);
  const to = await tileCentre(host.page, players[3].name);

  await host.page.mouse.move(from.x, from.y);
  await host.page.mouse.down();
  await host.page.mouse.move(to.x, to.y, { steps: 24 });
  await host.page.mouse.up();

  // The seating actually changed on the server...
  await expect
    .poll(async () => (await seatOrder(host.page, gameId)).join(','), { timeout: 10_000 })
    .not.toBe(before.join(','));

  const after = await seatOrder(host.page, gameId);
  // ...as a SWAP: same members, contiguous seats, exactly two moved.
  expect(after.slice().sort()).toEqual(before.slice().sort());
  const moved = after.filter((id, i) => id !== before[i]);
  expect(moved).toHaveLength(2);

  // ...and another player's client sees the same ring (it is shared state,
  // not a local view preference).
  await expect
    .poll(async () => (await seatOrder(observer.page, gameId)).join(','), { timeout: 10_000 })
    .toBe(after.join(','));
});

test('a tap on the life buttons is not treated as a drag', async ({ browser }) => {
  const { players, gameId, host } = await setupSeededGame(browser, [
    'leader',
    'assassin',
    'assassin',
    'traitor',
  ]);
  const before = await seatOrder(host.page, gameId);
  const target = players[2];

  await host.page.getByRole('button', { name: `Decrease ${target.name} life` }).click();

  // Life went down...
  await expect
    .poll(async () => {
      const docs = await fetchPlayerDocs(host.page, gameId);
      return docs.find((d) => d.user_id === target.userId)?.life_total;
    }, { timeout: 10_000 })
    .toBeLessThan(40);

  // ...and the seating did not move.
  expect((await seatOrder(host.page, gameId)).join(',')).toBe(before.join(','));
});

// Regression: a press that slides a few pixels (trackpad twitch, touch) used
// to cross DraggableSeat's 6px slop, capture the pointer away from the
// Pressable, and silently eat the tap — no error, no life change, perceived
// as lag. handlePointerDown now refuses to arm a drag from a button.
test('a sloppy press on a life button still registers', async ({ browser }) => {
  const { players, gameId, host } = await setupSeededGame(browser, [
    'leader',
    'assassin',
    'assassin',
    'traitor',
  ]);
  const before = await seatOrder(host.page, gameId);
  const target = players[2];

  const plus = host.page.getByRole('button', { name: `Increase ${target.name} life` });
  const box = await plus.boundingBox();
  if (!box) throw new Error('life button not visible');

  // Press, slide 8px (past the 6px drag slop), release — on the button.
  await host.page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await host.page.mouse.down();
  await host.page.mouse.move(box.x + box.width / 2 + 8, box.y + box.height / 2 + 3, { steps: 4 });
  await host.page.mouse.up();

  // The tap must land...
  await expect
    .poll(async () => {
      const docs = await fetchPlayerDocs(host.page, gameId);
      return docs.find((d) => d.user_id === target.userId)?.life_total;
    }, { timeout: 10_000 })
    .toBeGreaterThan(40);

  // ...without the slide being read as a seat drag.
  expect((await seatOrder(host.page, gameId)).join(',')).toBe(before.join(','));
});
