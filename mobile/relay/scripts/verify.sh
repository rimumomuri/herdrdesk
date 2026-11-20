#!/bin/sh
# Default is bind-free and never invokes installed hc. --http runs finite
# synthetic loopback servers and closes all sockets/threads in unittest cleanup.
set -eu
cd "$(dirname "$0")/.."
export PYTHONDONTWRITEBYTECODE=1
case "${1:-}" in
  '')
    python3 -m unittest test_relay.CoreTests test_relay.TokenTests test_relay.LiveTests -v
    printf '%s\n' 'HTTP listener/auth/framing/timeout integration: NOT RUN (use --http only in an approved bind-capable environment).'
    ;;
  --http)
    python3 -m unittest discover -s . -p 'test_relay.py' -v
    ;;
  *) printf '%s\n' 'usage: sh mobile/relay/scripts/verify.sh [--http]' >&2; exit 2 ;;
esac
