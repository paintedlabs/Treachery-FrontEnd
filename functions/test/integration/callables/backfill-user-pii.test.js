'use strict';

/**
 * INTEGRATION: functions/scripts/backfill-user-pii.js
 *
 * The backfill a developer runs against production to move email addresses,
 * phone numbers and FCM tokens off public profiles. These tests cover where
 * it goes: --apply refuses to run without --project, and a run names its
 * project, where that id came from, and the emulator or live Firestore before
 * it reads anything. Every run here has FIRESTORE_EMULATOR_HOST pointing at
 * the suite's emulator, and the only runs that read are dry runs of the
 * suite's default database, so nothing is written.
 */

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.resolve(__dirname, '../../../scripts/backfill-user-pii.js');
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-test';
// The suite's emulator; helpers.js uses the same default when it isn't set.
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8288';

/**
 * Runs the script on the command line with the suite's environment plus
 * `env` (an undefined value removes a variable), and always with Firestore
 * on the suite's emulator.
 */
function runScript(args, env = {}) {
  return spawnSync(process.execPath, [SCRIPT, ...args], {
    env: { ...process.env, ...env, FIRESTORE_EMULATOR_HOST: EMULATOR_HOST },
    encoding: 'utf8',
    timeout: 120_000,
  });
}

describe('backfill-user-pii — where it writes', () => {
  it('on the command line, --apply without --project stops before printing or reading anything', () => {
    const result = runScript(['--apply'], { GOOGLE_CLOUD_PROJECT: PROJECT_ID, GCLOUD_PROJECT: PROJECT_ID });
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /--apply needs --project/);
  });

  it('on the command line, a dry run names its project and where that id came from before anything else', () => {
    const runs = [
      [['--project', PROJECT_ID], {}, '--project'],
      [[], { GOOGLE_CLOUD_PROJECT: undefined, GCLOUD_PROJECT: PROJECT_ID }, 'GCLOUD_PROJECT'],
    ];
    for (const [args, env, source] of runs) {
      // The suite's own default database, read and never written.
      const result = runScript(args, env);
      assert.equal(result.status, 0, result.stderr);
      assert.deepEqual(result.stdout.split('\n').slice(0, 3), [
        `project:  ${PROJECT_ID} (from ${source})`,
        `target:   emulator ${EMULATOR_HOST}`,
        'mode:     DRY RUN (no writes)',
      ]);
      assert.match(result.stdout, /DRY RUN — nothing was written\. Re-run with --project <id> --apply to migrate\./);
    }
  });
});
