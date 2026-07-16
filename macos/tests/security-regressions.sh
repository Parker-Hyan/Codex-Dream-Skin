#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
NODE="${NODE:-/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node}"
[ -x "$NODE" ] || { printf 'Codex bundled Node.js was not found: %s\n' "$NODE" >&2; exit 1; }

TMP="$(/usr/bin/mktemp -d /tmp/codex-dream-skin-security.XXXXXX)"
VICTIM_PID=""
cleanup() {
  if [ -n "$VICTIM_PID" ]; then /bin/kill -TERM "$VICTIM_PID" 2>/dev/null || true; fi
  /bin/rm -rf "$TMP"
}
trap cleanup EXIT

# A healthy HTTP endpoint is insufficient when its listener is not Codex.
(
  . "$ROOT/scripts/common-macos.sh"
  port_belongs_to_codex() { return 1; }
  cdp_http_ready() { return 0; }
  listener_pids() { printf '%s\n' "$$"; }
  if verified_cdp_endpoint 9341; then
    printf 'Unverified CDP endpoint was accepted.\n' >&2
    exit 1
  fi
)

if /usr/bin/grep -q 'verified_cdp_endpoint.*||.*cdp_http_ready' "$ROOT/scripts/common-macos.sh"; then
  printf 'wait_for_cdp still bypasses endpoint identity verification.\n' >&2
  exit 1
fi
if /usr/bin/grep -q 'continuing with soft verification' "$ROOT/scripts/start-dream-skin-macos.sh"; then
  printf 'The launcher still accepts an HTTP-only CDP endpoint.\n' >&2
  exit 1
fi

# A caller-provided executable must not bypass runtime signature validation.
(
  . "$ROOT/scripts/common-macos.sh"
  NODE=/bin/sh
  RUNTIME_NODE=/previously-validated/node
  CODEX_RUNTIME_VALIDATED="true"
  discover_codex_app() { DISCOVER_CALLED="true"; CODEX_BUNDLE="/tmp/fake-codex.app"; }
  require_macos_runtime() { VALIDATE_CALLED="true"; CODEX_RUNTIME_VALIDATED="true"; NODE="/validated/node"; }
  ensure_node_runtime
  [ "${DISCOVER_CALLED:-false}" = "true" ]
  [ "${VALIDATE_CALLED:-false}" = "true" ]
  [ "$NODE" = "/validated/node" ]
)

if /usr/bin/grep -q '/usr/bin/python3\|^[[:space:]]*eval ' "$ROOT/scripts/common-macos.sh"; then
  printf 'Runtime resolution still depends on python3 or eval.\n' >&2
  exit 1
fi

# Incomplete state must fail closed and must not terminate a recycled PID.
HOME="$TMP/home"
/bin/mkdir -p "$HOME/Library/Application Support/CodexDreamSkinStudio"
(
  export HOME
  . "$ROOT/scripts/common-macos.sh"
  NODE="$NODE"
  "$NODE" -e 'setInterval(() => {}, 1000)' "$TMP/unrelated-injector.mjs" --watch &
  VICTIM_PID="$!"
  export VICTIM_PID
  "$NODE" -e '
    const fs = require("node:fs");
    const [file, pid, nodePath, injectorPath] = process.argv.slice(1);
    fs.writeFileSync(file, JSON.stringify({
      schemaVersion: 4,
      injectorPid: Number(pid),
      nodePath,
      injectorPath
    }));
  ' "$STATE_PATH" "$VICTIM_PID" "$NODE" "$INJECTOR"
  if stop_recorded_injector >/dev/null 2>&1; then
    printf 'Incomplete injector identity was accepted.\n' >&2
    exit 1
  fi
  /bin/kill -0 "$VICTIM_PID"
  /bin/kill -TERM "$VICTIM_PID" 2>/dev/null || true
  VICTIM_PID=""
)

# A complete, exact identity must still allow the recorded injector to stop.
(
  export HOME
  . "$ROOT/scripts/common-macos.sh"
  NODE="$NODE"
  "$NODE" -e 'setInterval(() => {}, 1000)' "$INJECTOR" --watch &
  EXPECTED_PID="$!"
  cleanup_expected() { /bin/kill -TERM "$EXPECTED_PID" 2>/dev/null || true; }
  trap cleanup_expected EXIT
  STARTED_AT=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    STARTED_AT="$(process_started_at "$EXPECTED_PID")"
    [ -n "$STARTED_AT" ] && break
    /bin/sleep 0.05
  done
  [ -n "$STARTED_AT" ] || { printf 'Could not observe the test injector start time.\n' >&2; exit 1; }
  "$NODE" -e '
    const fs = require("node:fs");
    const [file, pid, startedAt, nodePath, injectorPath] = process.argv.slice(1);
    fs.writeFileSync(file, JSON.stringify({
      schemaVersion: 4,
      injectorPid: Number(pid),
      injectorStartedAt: startedAt,
      nodePath,
      injectorPath
    }));
  ' "$STATE_PATH" "$EXPECTED_PID" "$STARTED_AT" "$NODE" "$INJECTOR"
  stop_recorded_injector
  if /bin/kill -0 "$EXPECTED_PID" 2>/dev/null; then
    printf 'An exactly recorded injector was not stopped.\n' >&2
    exit 1
  fi
  wait "$EXPECTED_PID" 2>/dev/null || true
  trap - EXIT
)

/bin/mkdir -p "$TMP/missing-theme"
if "$NODE" "$ROOT/scripts/injector.mjs" --check-payload --theme-dir "$TMP/missing-theme" \
  >"$TMP/missing-theme.out" 2>"$TMP/missing-theme.err"; then
  printf 'An explicit theme directory without theme.json was accepted.\n' >&2
  exit 1
fi
/usr/bin/grep -q 'Requested theme config does not exist' "$TMP/missing-theme.err"

printf 'PASS: strict CDP identity, signed runtime, conservative PID stop, and explicit theme selection.\n'
