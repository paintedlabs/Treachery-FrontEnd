'use strict';

/**
 * INTEGRATION: functions/scripts/reset-email-display-names.js
 *
 * The backfill a developer runs against production to take email addresses
 * out of public names, rehearsed through its own exported functions on the
 * Firestore emulator. The script scans whole collections, so each rehearsal
 * gets a named database of its own: the rest of the suite leaves users,
 * seats and friend requests in the default one. The seed holds email names
 * on profiles, on seats in waiting, in-progress and finished games and on
 * friend requests; names with an "@" that aren't email addresses; names
 * without one; and enough documents to cross the script's 200-document read
 * pages and BulkWriter's 20-write batches.
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { getApp } = require('firebase-admin/app');
const { getFirestore, Query, Timestamp } = require('firebase-admin/firestore');
const h = require('./helpers');
const backfill = require('../../../scripts/reset-email-display-names');

const SCRIPT = path.resolve(__dirname, '../../../scripts/reset-email-display-names.js');
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-test';
// helpers.js points this at the suite's emulator when it isn't set.
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST;
const CREATED_AT = Timestamp.fromMillis(Date.UTC(2026, 6, 1));

const databases = [];

after(async () => {
  await Promise.all(databases.map((db) => db.terminate().catch(() => {})));
  await h.shutdown();
});

/**
 * An emptied database of the rehearsal's own, and the script's view of it:
 * every write the script queues is recorded (an update that changes nothing
 * leaves no other trace, not even a new updateTime), and `afterRead` runs
 * right after the script reads a page, before the script sees it.
 */
async function rehearsalDatabase(databaseId) {
  const res = await fetch(
    `http://${EMULATOR_HOST}/emulator/v1/projects/${PROJECT_ID}/databases/${databaseId}/documents`,
    { method: 'DELETE' }
  );
  assert.ok(res.ok, `could not empty ${databaseId}: HTTP ${res.status}`);
  const db = getFirestore(getApp(), databaseId);
  databases.push(db);
  const run = { db, writes: [], afterRead: null };

  const watch = (query) =>
    new Proxy(query, {
      get(target, prop) {
        if (prop === 'get') {
          return async () => {
            const snap = await target.get();
            if (run.afterRead) await run.afterRead(snap.docs);
            return snap;
          };
        }
        const value = target[prop];
        if (typeof value !== 'function') return value;
        return (...args) => {
          const result = value.apply(target, args);
          return result instanceof Query ? watch(result) : result;
        };
      },
    });

  run.scriptDb = new Proxy(db, {
    get(target, prop) {
      if (prop === 'collection' || prop === 'collectionGroup') {
        return (...args) => watch(target[prop](...args));
      }
      if (prop === 'bulkWriter') {
        return (...options) =>
          new Proxy(target.bulkWriter(...options), {
            get(writer, method) {
              if (['create', 'set', 'update', 'delete'].includes(method)) {
                return (ref, ...args) => {
                  run.writes.push({ method, path: ref.path, data: args[0], precondition: args[1] });
                  return writer[method](ref, ...args);
                };
              }
              const value = writer[method];
              return typeof value === 'function' ? value.bind(writer) : value;
            },
          });
      }
      const value = target[prop];
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
  return run;
}

/** Writes each `{ path, data }` of `docs`. */
async function seed(db, docs) {
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + 400)) batch.set(db.doc(doc.path), doc.data);
    // Deliberate sequential await (no-await-in-loop).
    await batch.commit();
  }
}

/** Each path's data and updateTime, or null for a doc that doesn't exist. */
async function readAll(db, paths) {
  const states = new Map();
  for (let i = 0; i < paths.length; i += 300) {
    // Deliberate sequential await (no-await-in-loop).
    const snaps = await db.getAll(...paths.slice(i, i + 300).map((p) => db.doc(p)));
    for (const snap of snaps) {
      states.set(snap.ref.path, snap.exists ? { data: snap.data(), updateTime: snap.updateTime } : null);
    }
  }
  return states;
}

function assertUntouched(docPath, before, now) {
  assert.ok(now, `${docPath} must still exist`);
  assert.deepEqual(now.data, before.data, `${docPath} must keep its data`);
  assert.ok(now.updateTime.isEqual(before.updateTime), `${docPath} must not be written`);
}

/** Every name the seed holds, and every name the script could make of one. */
function namesIn(docs) {
  const names = new Set();
  for (const { data, reset } of docs) {
    for (const field of ['display_name', 'from_display_name', 'email']) {
      const value = data[field];
      if (typeof value !== 'string') continue;
      names.add(value);
      const localPart = value.split('@')[0].trim();
      if (value.includes('@') && localPart !== '') names.add(localPart);
    }
    if (reset) names.add(reset.value);
  }
  return names;
}

function assertNoNames(lines, names) {
  const output = lines.join('\n');
  for (const name of names) {
    assert.ok(!output.includes(name), `the output must never contain a name, but has ${JSON.stringify(name)}`);
  }
}

/**
 * The rehearsal's documents. `reset` marks each one the script must
 * rewrite, with the one field and the name it must get; every other
 * document must come through untouched.
 */
function rehearsalSeed() {
  const docs = [];
  const add = (docPath, data, field, newName) =>
    docs.push({ path: docPath, data, reset: newName ? { field, value: newName } : null });
  const user = (id, data, newName) => add(`users/${id}`, data, 'display_name', newName);
  const game = (id, state) => add(`games/${id}`, { host_id: 'plain', state, game_mode: 'treachery' });
  const seat = (gameId, order, name, newName) =>
    add(
      `games/${gameId}/players/p${order}`,
      { user_id: `${gameId}-${order}`, display_name: name, order_id: order, role: null, life_total: 40 },
      'display_name',
      newName
    );
  const request = (id, name, newName, status = 'pending') =>
    add(
      `friend_requests/${id}`,
      { from_user_id: `${id}-sender`, from_display_name: name, to_user_id: 'plain', status, created_at: CREATED_AT },
      'from_display_name',
      newName
    );

  // Profiles. The first still holds the legacy public copy of its email,
  // which is backfill-user-pii.js's to move, not this script's.
  user(
    'email-full',
    {
      display_name: 'quinlan.vexworth@example.com',
      email: 'quinlan.vexworth@example.com',
      elo: 1612,
      friend_ids: ['plain'],
      deck_stats: { Atraxa: { wins: 2, losses: 1 } },
      created_at: CREATED_AT,
    },
    'Quinlan.vexworth'
  );
  user('email-accented', { display_name: 'élodie.brassard@exemple.fr', elo: 1500 }, 'Élodie.brassard');
  user('email-tagged', { display_name: 'marisol_okonkwo+treachery@mail.example.org' }, 'Marisol_okonkwo+treachery');
  user('handle-spaced', { display_name: 'Brannoc @ Home', elo: 1480 });
  user('handle-leading', { display_name: '@quillfeather' });
  user('handle-no-dot', { display_name: 'tidewater@harbor' });
  user('handle-two-ats', { display_name: 'ashgrove@oak@elm.io' });
  user('plain', { display_name: 'Thessaly Okafor-Wren', elo: 1533 });
  user('no-name', { elo: 1500 });
  for (let i = 0; i < 230; i++) {
    const n = String(i).padStart(3, '0');
    if (i % 2 === 0) user(`bulk-${n}`, { display_name: `bulkfolk.${n}.zq@example.net`, elo: 1500 }, `Bulkfolk.${n}.zq`);
    else user(`bulk-${n}`, { display_name: `Bulkfolk Plain ${n} Zq`, elo: 1500 });
  }

  // Seats in each game state, a seat whose game doc is gone, and a
  // "players" doc that isn't a seat.
  game('lobby', 'waiting');
  seat('lobby', 0, 'corvina.lestrange@example.com', 'Corvina.lestrange');
  seat('lobby', 1, 'Sable @ Dusk');
  seat('lobby', 2, 'Hollis Drummond');
  game('table', 'in_progress');
  seat('table', 0, 'thaddeus.quorne@example.io', 'Thaddeus.quorne');
  seat('table', 1, '@nightjar');
  seat('table', 2, 'Mirabel Steadwick');
  game('history', 'finished');
  seat('history', 0, 'wilhelmina.ashdown@example.co.uk', 'Wilhelmina.ashdown');
  seat('history', 1, 'fenwick@lodge');
  seat('history', 2, 'Deleted player');
  seat('vanished', 0, 'orla.vantassel@example.com', 'Orla.vantassel');
  add('tournaments/cup/players/entrant', { display_name: 'not.a.seat@example.com' });
  for (let g = 0; g < 30; g++) {
    const gameId = `bulk-${String(g).padStart(2, '0')}`;
    game(gameId, 'finished');
    for (let s = 0; s < 8; s++) {
      const n = `${gameId}-${s}`;
      if (s % 2 === 0) seat(gameId, s, `seatfolk.${n}.zq@example.net`, `Seatfolk.${n}.zq`);
      else seat(gameId, s, `Seatfolk Plain ${n} Zq`);
    }
  }

  // Friend requests: the sender's name, as the recipient sees it.
  request('email-pending', 'quinlan.vexworth@example.com', 'Quinlan.vexworth');
  request('email-accepted', 'élodie.brassard@exemple.fr', 'Élodie.brassard', 'accepted');
  request('handle', 'Brannoc @ Home');
  request('plain', 'Thessaly Okafor-Wren');
  for (let i = 0; i < 220; i++) {
    const n = String(i).padStart(3, '0');
    if (i % 2 === 0) request(`bulk-${n}`, `askfolk.${n}.zq@example.net`, `Askfolk.${n}.zq`);
    else request(`bulk-${n}`, `Askfolk Plain ${n} Zq`);
  }
  return docs;
}

describe('reset-email-display-names — rehearsal', () => {
  const docs = rehearsalSeed();
  const paths = docs.map((d) => d.path);
  const names = namesIn(docs);
  // What the dry run reports and --apply writes, by collection.
  const users = { scanned: 239, reset: 118, kept: 4 };
  const seats = {
    scanned: 251,
    reset: 124,
    kept: 3,
    byState: { waiting: 1, in_progress: 1, finished: 121, 'no game doc': 1 },
  };
  const requests = { scanned: 224, reset: 112, kept: 1 };
  let run;
  let afterApply;

  before(async () => {
    run = await rehearsalDatabase('reset-email-rehearsal');
    await seed(run.db, docs);
  });

  it('a dry run reports the email names and the other "@" names apart, and writes nothing', async () => {
    const before = await readAll(run.db, paths);
    const output = [];
    const log = (line) => output.push(line);

    const { stats, totals } = await backfill.resetEmailDisplayNames(run.scriptDb, { apply: false, log, logError: log });

    assert.deepEqual(stats, { users, seats, requests });
    assert.deepEqual(totals, { planned: 354, updated: 0, skipped: 0, failed: 0 });
    assert.deepEqual(run.writes, [], 'a dry run queues no write');
    const now = await readAll(run.db, paths);
    for (const p of paths) assertUntouched(p, before.get(p), now.get(p));

    assert.match(output.join('\n'), /^ {2}other names with "@" \(kept\): +4$/m);
    assert.match(output.join('\n'), /^ {2}other names with "@" \(kept\): +3$/m);
    assert.match(output.join('\n'), /^ {2}other sender names with "@" \(kept\): +1$/m);
    assert.match(output.join('\n'), /DRY RUN — nothing was written/);
    assertNoNames(output, names);
  });

  it('--apply resets exactly the email names, and only their name field', async () => {
    const before = await readAll(run.db, paths);
    const output = [];
    const log = (line) => output.push(line);

    const { stats, totals } = await backfill.resetEmailDisplayNames(run.scriptDb, { apply: true, log, logError: log });
    afterApply = await readAll(run.db, paths);

    assert.deepEqual(stats, { users, seats, requests });
    assert.deepEqual(totals, { planned: 354, updated: 354, skipped: 0, failed: 0 });
    const byPath = (a, b) => a.path.localeCompare(b.path);
    assert.deepEqual(
      run.writes.map(({ method, path: p, data }) => ({ method, path: p, data })).sort(byPath),
      docs
        .filter((d) => d.reset)
        .map((d) => ({ method: 'update', path: d.path, data: { [d.reset.field]: d.reset.value } }))
        .sort(byPath),
      'one update per email name, of that name alone'
    );
    for (const write of run.writes) {
      assert.ok(
        write.precondition?.lastUpdateTime instanceof Timestamp,
        `${write.path}: the update must require the doc to be unchanged since it was read`
      );
    }

    for (const doc of docs) {
      const was = before.get(doc.path);
      const now = afterApply.get(doc.path);
      if (doc.reset) {
        assert.deepEqual(
          now.data,
          { ...was.data, [doc.reset.field]: doc.reset.value },
          `${doc.path}: only the name changes`
        );
      } else {
        assertUntouched(doc.path, was, now);
      }
    }
    assertNoNames(output, names);
  });

  it('a second --apply finds nothing left to reset and writes nothing', async () => {
    run.writes.length = 0;
    const output = [];
    const log = (line) => output.push(line);

    const { stats, totals } = await backfill.resetEmailDisplayNames(run.scriptDb, { apply: true, log, logError: log });

    assert.deepEqual(stats, {
      users: { ...users, reset: 0 },
      seats: { ...seats, reset: 0, byState: {} },
      requests: { ...requests, reset: 0 },
    });
    assert.deepEqual(totals, { planned: 0, updated: 0, skipped: 0, failed: 0 });
    assert.deepEqual(run.writes, []);
    const now = await readAll(run.db, paths);
    for (const p of paths) assertUntouched(p, afterApply.get(p), now.get(p));
    assertNoNames(output, names);
  });
});

describe('reset-email-display-names — a doc changed after the script read it', () => {
  it('is skipped, never overwritten or recreated, and a re-run picks it up if it still needs it', async () => {
    const run = await rehearsalDatabase('reset-email-race');
    const docs = [
      { path: 'users/renamed', data: { display_name: 'renata.quickfall@example.com' } },
      { path: 'users/deleted', data: { display_name: 'dorian.vale@example.com' } },
      { path: 'users/elo-moved', data: { display_name: 'ingrid.halloway@example.com', elo: 1500 } },
      { path: 'users/steady', data: { display_name: 'stellan.marsh@example.com' } },
      { path: 'games/finished', data: { state: 'finished', game_mode: 'treachery' } },
      { path: 'games/finished/players/p0', data: { user_id: 'gone', display_name: 'percival.thorne@example.com' } },
      { path: 'friend_requests/withdrawn', data: { from_user_id: 'x', from_display_name: 'gwendolyn.ash@example.com' } },
    ];
    await seed(run.db, docs);
    const get = async (p) => (await run.db.doc(p).get()).data() ?? null;

    // Each change lands right after the script reads the doc's page, before
    // it queues the doc's update: a rename, an account deletion, a game's
    // ELO, deleteAccount anonymizing a seat, a withdrawn request.
    const changes = new Map([
      ['users/renamed', (ref) => ref.update({ display_name: 'Renata Q' })],
      ['users/deleted', (ref) => ref.delete()],
      ['users/elo-moved', (ref) => ref.update({ elo: 1523 })],
      ['games/finished/players/p0', (ref) => ref.update({ display_name: 'Deleted player' })],
      ['friend_requests/withdrawn', (ref) => ref.delete()],
    ]);
    run.afterRead = async (pageDocs) => {
      for (const doc of pageDocs) {
        const change = changes.get(doc.ref.path);
        if (!change) continue;
        changes.delete(doc.ref.path);
        // Deliberate sequential await (no-await-in-loop).
        await change(doc.ref);
      }
    };
    const output = [];
    const log = (line) => output.push(line);

    const first = await backfill.resetEmailDisplayNames(run.scriptDb, { apply: true, log, logError: log });

    assert.equal(changes.size, 0, 'every change ran');
    assert.deepEqual(first.totals, { planned: 6, updated: 1, skipped: 5, failed: 0 });
    assert.deepEqual(await get('users/renamed'), { display_name: 'Renata Q' }, 'the rename stands');
    assert.equal(await get('users/deleted'), null, 'a deleted profile is not recreated');
    assert.deepEqual(
      await get('users/elo-moved'),
      { display_name: 'ingrid.halloway@example.com', elo: 1523 },
      'the new ELO stands, and the name waits for a re-run'
    );
    assert.deepEqual(await get('users/steady'), { display_name: 'Stellan.marsh' });
    assert.equal((await get('games/finished/players/p0')).display_name, 'Deleted player');
    assert.equal(await get('friend_requests/withdrawn'), null, 'a deleted request is not recreated');

    run.afterRead = null;
    const second = await backfill.resetEmailDisplayNames(run.scriptDb, { apply: true, log, logError: log });

    assert.deepEqual(second.totals, { planned: 1, updated: 1, skipped: 0, failed: 0 });
    assert.deepEqual(await get('users/elo-moved'), { display_name: 'Ingrid.halloway', elo: 1523 });
    assertNoNames(output, namesIn([...docs, { data: { display_name: 'Renata Q' } }]));
  });
});

describe('reset-email-display-names — where it writes', () => {
  let defaultLookups = 0;
  const findDefaultProject = async () => {
    defaultLookups++;
    return 'demo-from-adc';
  };

  it('refuses --apply without --project, wherever else a project could come from', async () => {
    defaultLookups = 0;
    for (const env of [
      {},
      { GOOGLE_CLOUD_PROJECT: 'demo-from-env' },
      { GCLOUD_PROJECT: 'demo-from-env' },
      { GCLOUD_PROJECT: 'demo-from-env', FIRESTORE_EMULATOR_HOST: EMULATOR_HOST },
    ]) {
      // Deliberate sequential await (no-await-in-loop).
      const target = await backfill.resolveTarget({ apply: true, projectId: null }, env, findDefaultProject);
      assert.match(target.error ?? '', /--apply needs --project/, JSON.stringify(env));
      assert.equal(target.projectId, undefined);
    }
    assert.equal(defaultLookups, 0, '--apply never looks for a default project');
  });

  it('names the project, where its id came from, and the emulator or live Firestore', async () => {
    const cases = [
      [
        { apply: true, projectId: 'demo-named' },
        { GCLOUD_PROJECT: 'demo-from-env' },
        ['project:  demo-named (from --project)', 'target:   LIVE Firestore', 'mode:     APPLY (writes)'],
      ],
      [
        { apply: true, projectId: 'demo-named' },
        { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8288' },
        ['project:  demo-named (from --project)', 'target:   emulator 127.0.0.1:8288', 'mode:     APPLY (writes)'],
      ],
      [
        { apply: false, projectId: null },
        { GOOGLE_CLOUD_PROJECT: 'demo-from-env' },
        ['project:  demo-from-env (from GOOGLE_CLOUD_PROJECT)', 'target:   LIVE Firestore', 'mode:     DRY RUN (no writes)'],
      ],
      [
        { apply: false, projectId: null },
        {},
        [
          'project:  demo-from-adc (from Application Default Credentials)',
          'target:   LIVE Firestore',
          'mode:     DRY RUN (no writes)',
        ],
      ],
    ];
    for (const [opts, env, lines] of cases) {
      // Deliberate sequential await (no-await-in-loop).
      const target = await backfill.resolveTarget(opts, env, findDefaultProject);
      assert.deepEqual(backfill.describeTarget(target, opts.apply), lines);
    }

    const emulatorWithoutId = await backfill.resolveTarget(
      { apply: false, projectId: null },
      { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8288' },
      findDefaultProject
    );
    assert.match(emulatorWithoutId.error ?? '', /pass --project/);
  });

  it('on the command line, --apply without --project stops before printing or reading anything', () => {
    const result = spawnSync(process.execPath, [SCRIPT, '--apply'], {
      env: { ...process.env, FIRESTORE_EMULATOR_HOST: EMULATOR_HOST, GCLOUD_PROJECT: PROJECT_ID },
      encoding: 'utf8',
      timeout: 60_000,
    });
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /--apply needs --project/);
  });

  it('on the command line, a dry run says where it goes before anything else', () => {
    // The suite's own default database, read and never written.
    const result = spawnSync(process.execPath, [SCRIPT, '--project', PROJECT_ID], {
      env: { ...process.env, FIRESTORE_EMULATOR_HOST: EMULATOR_HOST },
      encoding: 'utf8',
      timeout: 120_000,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(result.stdout.split('\n').slice(0, 3), [
      `project:  ${PROJECT_ID} (from --project)`,
      `target:   emulator ${EMULATOR_HOST}`,
      'mode:     DRY RUN (no writes)',
    ]);
    assert.match(result.stdout, /DRY RUN — nothing was written/);
  });
});
