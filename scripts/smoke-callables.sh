#!/usr/bin/env bash
#
# Post-deploy smoke check: every onCall function must be publicly reachable.
#
# Why this exists: on 2026-08-14 `createGame` and `registerFcmToken` sat in
# production with EMPTY Cloud Run IAM policies — no allUsers/run.invoker
# binding — so every browser call got a 403 HTML page instead of the function.
# With no CORS headers on that response the browser reported it as a CORS
# error, which made it look like an app bug. Game creation was broken on
# staging and in the shipped TestFlight build while CI was entirely green:
# every other gate tests the CODE, and the code was fine. Only the DEPLOYED
# state was broken, and nothing looked at that.
#
# The check is an unauthenticated CORS preflight (OPTIONS). It never invokes
# a function body, so it is side-effect free and needs no credentials.
#
# Usage: scripts/smoke-callables.sh <project-id> <origin> [region]
set -euo pipefail

PROJECT="${1:?usage: smoke-callables.sh <project-id> <origin> [region]}"
ORIGIN="${2:?usage: smoke-callables.sh <project-id> <origin> [region]}"
REGION="${3:-us-central1}"

SOURCE_FILE="$(dirname "$0")/../functions/index.js"

# Derive the list from source so a new callable is covered automatically and
# this can't rot into a stale hardcoded list. Only `onCall` exports are
# public; onSchedule/onDocument* triggers are correctly NOT publicly
# invokable and would fail this check by design.
# while-read rather than mapfile: mapfile is bash 4+, and stock macOS ships
# bash 3.2, so a developer running this locally would just get "command not
# found".
CALLABLES=()
while IFS= read -r fn; do
  [ -n "$fn" ] && CALLABLES+=("$fn")
done < <(
  grep -oE '^exports\.[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*onCall' "$SOURCE_FILE" \
    | sed -E 's/^exports\.//; s/[[:space:]]*=[[:space:]]*onCall$//' \
    | sort -u
)

if [ "${#CALLABLES[@]}" -eq 0 ]; then
  echo "FAIL: found no onCall exports in $SOURCE_FILE — is the parse broken?" >&2
  exit 1
fi

echo "Smoke-testing ${#CALLABLES[@]} callables in $PROJECT ($REGION) from origin $ORIGIN"
echo

# A just-deployed revision can need a moment to start serving, and an IAM
# binding takes a beat to propagate, so retry before calling it a failure.
ATTEMPTS=5
SLEEP_SECONDS=6
failures=()

for fn in "${CALLABLES[@]}"; do
  url="https://${REGION}-${PROJECT}.cloudfunctions.net/${fn}"
  code=""
  acao=""

  for attempt in $(seq 1 "$ATTEMPTS"); do
    headers="$(curl -sS -D - -o /dev/null -X OPTIONS \
      -H "Origin: ${ORIGIN}" \
      -H 'Access-Control-Request-Method: POST' \
      -H 'Access-Control-Request-Headers: content-type' \
      --max-time 20 "$url" 2>/dev/null || true)"

    code="$(printf '%s' "$headers" | awk 'NR==1 {print $2}')"
    acao="$(printf '%s' "$headers" | tr -d '\r' \
      | grep -i '^access-control-allow-origin:' | head -1 || true)"

    # 204 with an ACAO header is the only healthy answer.
    if [ "$code" = "204" ] && [ -n "$acao" ]; then
      break
    fi
    [ "$attempt" -lt "$ATTEMPTS" ] && sleep "$SLEEP_SECONDS"
  done

  if [ "$code" = "204" ] && [ -n "$acao" ]; then
    printf '  ok    %-24s %s\n' "$fn" "$code"
  else
    printf '  FAIL  %-24s %s %s\n' "$fn" "${code:-no-response}" \
      "$([ -z "$acao" ] && echo '(no Access-Control-Allow-Origin)')"
    failures+=("$fn")
  fi
done

echo
if [ "${#failures[@]}" -gt 0 ]; then
  cat >&2 <<MSG
FAIL: ${#failures[@]} callable(s) are not publicly reachable: ${failures[*]}

A 403 with no CORS header almost always means the Cloud Run service is
missing its public invoker binding. Firebase normally sets this on deploy;
when it is absent the browser reports a misleading CORS error. Note the
Cloud Run service name is the function name LOWERCASED:

  gcloud run services add-iam-policy-binding <lowercased-name> \\
    --region=${REGION} --project=${PROJECT} \\
    --member=allUsers --role=roles/run.invoker

Then re-run this script to confirm.
MSG
  exit 1
fi

echo "All ${#CALLABLES[@]} callables reachable."
