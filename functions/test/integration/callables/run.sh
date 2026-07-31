#!/usr/bin/env bash
#
# Boots the Firebase emulators on this suite's own ports and runs the
# Cloud Functions integration tests against them.
#
#   cd functions && npm run test:integration
#
# Optional args are forwarded to `node --test`, e.g.
#   npm run test:integration -- --test-name-pattern "win condition"
#
# Ports default to auth 9299 / firestore 8288 / functions 5201 (deliberately
# clear of the Playwright E2E suite, which uses the repo-root firebase.json).
# If something else already holds one of them, retarget without editing any
# committed file:
#   INTEGRATION_AUTH_PORT=9399 npm run test:integration
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCTIONS_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$FUNCTIONS_DIR"

BASE_CONFIG="test/integration/callables/firebase.emulators.json"

AUTH_PORT="${INTEGRATION_AUTH_PORT:-9299}"
FIRESTORE_PORT="${INTEGRATION_FIRESTORE_PORT:-8288}"
FUNCTIONS_PORT="${INTEGRATION_FUNCTIONS_PORT:-5201}"
export INTEGRATION_FUNCTIONS_PORT="$FUNCTIONS_PORT"

# ── firebase-tools ──────────────────────────────────────────────
if ! command -v firebase >/dev/null 2>&1; then
  echo "error: the 'firebase' CLI is not on PATH." >&2
  echo "       install it with:  npm install -g firebase-tools" >&2
  exit 1
fi

# ── Java 21+ (firebase-tools refuses to start the emulators below 21) ──
java_major() {
  local out
  out="$("$1" -version 2>&1 | head -1)" || return 1
  # matches:  openjdk version "23.0.2" ...   /   java version "1.8.0_401"
  printf '%s' "$out" | sed -E 's/^[^"]*"([0-9]+).*/\1/'
}

java_ok() {
  local bin="$1" major
  [ -x "$bin" ] || return 1
  major="$(java_major "$bin" 2>/dev/null || true)"
  case "$major" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$major" -ge 21 ]
}

CANDIDATE_HOMES=()
[ -n "${JAVA_HOME:-}" ] && CANDIDATE_HOMES+=("$JAVA_HOME")
if [ -x /usr/libexec/java_home ]; then
  for v in 25 24 23 22 21; do
    home="$(/usr/libexec/java_home -v "$v" 2>/dev/null || true)"
    [ -n "$home" ] && CANDIDATE_HOMES+=("$home")
  done
fi
for v in 25 24 23 22 21; do
  for home in \
    "/opt/homebrew/opt/openjdk@$v/libexec/openjdk.jdk/Contents/Home" \
    "/usr/local/opt/openjdk@$v/libexec/openjdk.jdk/Contents/Home" \
    "/usr/lib/jvm/temurin-$v-jdk" \
    "/usr/lib/jvm/java-$v-openjdk-amd64"; do
    [ -d "$home" ] && CANDIDATE_HOMES+=("$home")
  done
done

SELECTED_JAVA_HOME=""
for home in "${CANDIDATE_HOMES[@]:-}"; do
  if java_ok "$home/bin/java"; then
    SELECTED_JAVA_HOME="$home"
    break
  fi
done

if [ -n "$SELECTED_JAVA_HOME" ]; then
  export JAVA_HOME="$SELECTED_JAVA_HOME"
  export PATH="$JAVA_HOME/bin:$PATH"
elif ! java_ok "$(command -v java || echo /nonexistent)"; then
  echo "error: the Firebase emulators need Java 21 or newer." >&2
  echo "       found: $(command -v java >/dev/null 2>&1 && java -version 2>&1 | head -1 || echo 'no java on PATH')" >&2
  echo "       fix:   brew install openjdk@23   (or set JAVA_HOME to a 21+ JDK)" >&2
  exit 1
fi

# ── Config (regenerated only when ports are overridden) ─────────
CONFIG="$BASE_CONFIG"
TMP_CONFIG=""
if [ "$AUTH_PORT" != "9299" ] || [ "$FIRESTORE_PORT" != "8288" ] || [ "$FUNCTIONS_PORT" != "5201" ]; then
  # Must live next to the template: firebase-tools resolves functions.source
  # relative to the directory holding the config file.
  TMP_CONFIG="test/integration/callables/.emulators.override.json"
  node -e '
    const fs = require("fs");
    const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    cfg.emulators.auth.port = Number(process.argv[3]);
    cfg.emulators.firestore.port = Number(process.argv[4]);
    cfg.emulators.functions.port = Number(process.argv[5]);
    fs.writeFileSync(process.argv[2], JSON.stringify(cfg, null, 2));
  ' "$BASE_CONFIG" "$TMP_CONFIG" "$AUTH_PORT" "$FIRESTORE_PORT" "$FUNCTIONS_PORT"
  CONFIG="$TMP_CONFIG"
fi

# ── Run ─────────────────────────────────────────────────────────
# The emulator streams a lot of noise to stdout, so the test reporter writes
# to its own file which is printed once the emulators have shut down.
RESULTS="$(mktemp "${TMPDIR:-/tmp}/treachery-integration.XXXXXX")"
cleanup() {
  rm -f "$RESULTS"
  [ -n "$TMP_CONFIG" ] && rm -f "$TMP_CONFIG"
  # Must end truthy: a failing last command in an EXIT trap overrides the
  # script's own exit status, which would report a green run as a failure.
  return 0
}
trap cleanup EXIT

CMD="node --test --test-concurrency=1 --test-reporter=spec"
CMD="$CMD --test-reporter-destination=$(printf '%q' "$RESULTS")"
for arg in "$@"; do CMD="$CMD $(printf '%q' "$arg")"; done
# Explicit glob rather than the directory, so helpers.js is never mistaken
# for a test file.
CMD="$CMD test/integration/callables/*.test.js"

set +e
firebase emulators:exec \
  --project=demo-test \
  --only auth,firestore,functions \
  --config="$CONFIG" \
  "$CMD"
STATUS=$?
set -e

echo
echo "════════════════ integration test results ════════════════"
cat "$RESULTS"

exit "$STATUS"
