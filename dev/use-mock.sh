#!/usr/bin/env bash
# Point the running plugin at the fake Seerr (dev/mock-seerr.js) and back,
# so the panel can be tried without touching a real instance.
#
#   dev/use-mock.sh on [--hostile]   start the mock, store its key, switch the URL
#   dev/use-mock.sh off              switch back to the saved URL, stop the mock
#   dev/use-mock.sh status
#
# The real API key stays in the keyring: keys are bound to the origin of the
# URL, so the mock gets its own entry and the real one is never sent to it.
# The real URL is saved before switching and restored by `off`. Coming back
# counts as a first run for the real server: no notification for requests
# already pending, and none for those that arrived while on the mock.
set -euo pipefail

PLUGIN=myouboku.omaseerr
PORT=${OMASEERR_MOCK_PORT:-5056}   # 5055 is the Docker Seerr of dev/compose.yaml
KEY=devkey1234567890
MOCK_URL="http://127.0.0.1:$PORT"
DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omaseerr-dev"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

shell() { omarchy-shell "$PLUGIN" "$@"; }

mock_running() { [[ -f "$DIR/mock.pid" ]] && kill -0 "$(cat "$DIR/mock.pid")" 2>/dev/null; }

case "${1:-}" in
  on)
    mkdir -p "$DIR"
    current="$(shell get url)"
    if [[ "$current" != "$MOCK_URL" ]]; then
      printf '%s\n' "$current" > "$DIR/real-url"
    fi
    if ! mock_running; then
      node "$HERE/mock-seerr.js" --port "$PORT" --key "$KEY" ${2:+"$2"} > "$DIR/mock.log" 2>&1 &
      echo $! > "$DIR/mock.pid"
      for _ in $(seq 20); do curl -sS -o /dev/null "$MOCK_URL/" 2>/dev/null && break; sleep 0.2; done
    fi
    printf '%s' "$KEY" | secret-tool store --label="OmaSeerr (mock Seerr)" \
      service "$PLUGIN" account api-key origin "$MOCK_URL"
    shell set url "$MOCK_URL" >/dev/null
    shell reloadKey >/dev/null
    echo "on: $MOCK_URL (real URL saved in $DIR/real-url, mock log in $DIR/mock.log)"
    ;;
  off)
    if [[ -f "$DIR/real-url" ]]; then
      shell set url "$(cat "$DIR/real-url")" >/dev/null
      shell reloadKey >/dev/null
      rm -f "$DIR/real-url"
      echo "off: back to the saved URL"
    else
      echo "off: no saved URL, the plugin's URL was left as it is" >&2
    fi
    if mock_running; then kill "$(cat "$DIR/mock.pid")"; fi
    rm -f "$DIR/mock.pid"
    secret-tool clear service "$PLUGIN" account api-key origin "$MOCK_URL" || true
    ;;
  status)
    url="$(shell get url)"
    mock_running && mock="mock running (pid $(cat "$DIR/mock.pid"))" || mock="mock not running"
    # The plugin's own status only while on the mock: the real one is off limits.
    if [[ "$url" == "$MOCK_URL" ]]; then echo "on the mock ($MOCK_URL)"; echo "$mock"; shell status
    else echo "on the real instance"; echo "$mock"; fi
    ;;
  *)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
