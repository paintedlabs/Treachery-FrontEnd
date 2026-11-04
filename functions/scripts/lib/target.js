/**
 * Where a backfill in scripts/ reads and writes: the Firestore project,
 * where its id came from, and the emulator or live Firestore.
 * reset-email-display-names.js and backfill-user-pii.js both print this
 * before they read anything, and both refuse --apply without an explicit
 * --project.
 */

const { applicationDefault } = require("firebase-admin/app");

/**
 * Where this run goes, as `{ projectId, source, emulatorHost }`, or
 * `{ error }` when it must not start. --apply needs --project, so it never
 * writes to a project picked up from the environment or from Application
 * Default Credentials. Without --project, a dry run uses
 * GOOGLE_CLOUD_PROJECT or GCLOUD_PROJECT, and failing those asks
 * `findDefaultProject` for the Application Default Credentials' project,
 * except on the emulator, which infers nothing from credentials.
 */
async function resolveTarget(opts, env, findDefaultProject = () => applicationDefault().getProjectId()) {
  const emulatorHost = env.FIRESTORE_EMULATOR_HOST || null;
  if (opts.projectId) {
    return { projectId: opts.projectId, source: "--project", emulatorHost };
  }
  if (opts.apply) {
    return {
      error:
        "--apply needs --project <id>. It never writes to a project taken from " +
        "GOOGLE_CLOUD_PROJECT, GCLOUD_PROJECT or Application Default Credentials.",
    };
  }
  for (const variable of ["GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT"]) {
    if (env[variable]) return { projectId: env[variable], source: variable, emulatorHost };
  }
  if (emulatorHost) {
    return { error: "FIRESTORE_EMULATOR_HOST is set but no project id — pass --project <id>." };
  }
  return {
    projectId: await findDefaultProject(),
    source: "Application Default Credentials",
    emulatorHost,
  };
}

/** The lines that say where the run goes, printed before it reads anything. */
function describeTarget({ projectId, source, emulatorHost }, apply) {
  return [
    `project:  ${projectId} (from ${source})`,
    `target:   ${emulatorHost ? `emulator ${emulatorHost}` : "LIVE Firestore"}`,
    `mode:     ${apply ? "APPLY (writes)" : "DRY RUN (no writes)"}`,
  ];
}

module.exports = { resolveTarget, describeTarget };
