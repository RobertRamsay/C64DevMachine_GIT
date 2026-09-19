#!/bin/bash
# ---------------------------------------------------------------------------
#  C64 Dev Machine - MCP setup helper (Pro edition, macOS)
#
#  Launched by the MCP-CON button. Same status tokens and same files as
#  setup-mcp.bat, so the editor polls it identically.
#
#  Usage:  setup-mcp.command [status_folder]
#
#  The pairing key is never written to the log.
# ---------------------------------------------------------------------------
set -u

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE="$SCRIPTDIR/bridge.mjs"

STATUSDIR="${1:-$HOME/.c64-dev-machine-mcp}"
STATUSDIR="${STATUSDIR%/}"
mkdir -p "$STATUSDIR" 2>/dev/null

STATUS="$STATUSDIR/mcp-setup-status.txt"
LOG="$STATUSDIR/mcp-setup-log.txt"
PAIRFILE="$STATUSDIR/mcp-pair.txt"
HOSTS=""

echo "[$(date)] MCP setup started" > "$LOG"
echo "script folder: $SCRIPTDIR" >> "$LOG"
echo "status folder: $STATUSDIR" >> "$LOG"

# A stale key from an earlier run must never be adopted.
rm -f "$PAIRFILE"

status() {
    printf '%s\n%s\n' "$1" "$2" > "$STATUS"
    echo "[$(date +%T)] $1 - $2" >> "$LOG"
}

finish() {
    echo "[$(date +%T)] MCP setup finished" >> "$LOG"
    exit 0
}

status CHECKING "Checking for Node.js"

if [ ! -f "$BRIDGE" ]; then
    status BRIDGE_MISSING "bridge.mjs was not found next to setup-mcp.command"
    finish
fi

find_node() {
    NODE=""
    for candidate in "$(command -v node 2>/dev/null)" \
                     /opt/homebrew/bin/node \
                     /usr/local/bin/node \
                     /usr/bin/node; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            NODE="$candidate"
            return 0
        fi
    done
    return 0
}

find_node
if [ -z "$NODE" ]; then
    status NODE_MISSING "Node.js is not installed"
    if command -v brew >/dev/null 2>&1; then
        status NODE_INSTALLING "Installing Node.js with Homebrew"
        brew install node >> "$LOG" 2>&1
        echo "brew exit code: $?" >> "$LOG"
        find_node
    fi
    if [ -z "$NODE" ]; then
        status NO_WINGET "Install Node.js 22 or newer from nodejs.org, then press MCP-CON again"
        open "https://nodejs.org/en/download" >/dev/null 2>&1
        finish
    fi
fi

echo "node: $NODE" >> "$LOG"
NVRAW="$("$NODE" --version 2>>"$LOG")"
echo "node version: $NVRAW" >> "$LOG"
NV="${NVRAW#v}"
NV="${NV%%.*}"
case "$NV" in
    ''|*[!0-9]*) NV=0 ;;
esac
if [ "$NV" -lt 22 ]; then
    status NODE_TOO_OLD "Found Node.js $NVRAW - version 22 or newer is required"
    finish
fi

status REGISTERING "Preparing the local pairing key"
if ! "$NODE" "$BRIDGE" --pair > "$PAIRFILE" 2>>"$LOG"; then
    rm -f "$PAIRFILE"
    status TOKEN_FAILED "Could not create the local pairing key. See mcp-setup-log.txt"
    finish
fi
chmod 600 "$HOME/.c64-dev-machine-mcp/token" 2>/dev/null
chmod 600 "$PAIRFILE" 2>/dev/null
echo "pairing key written for the editor to collect" >> "$LOG"

if command -v codex >/dev/null 2>&1; then
    status REGISTERING "Registering with Codex CLI"
    echo "--- codex mcp add ---" >> "$LOG"
    codex mcp add c64-dev-machine -- "$NODE" "$BRIDGE" >> "$LOG" 2>&1
    echo "codex exit code: $?" >> "$LOG"
    HOSTS="$HOSTS Codex"
fi

if command -v claude >/dev/null 2>&1; then
    status REGISTERING "Registering with Claude Code"
    echo "--- claude mcp add ---" >> "$LOG"
    claude mcp add --scope user c64-dev-machine -- "$NODE" "$BRIDGE" >> "$LOG" 2>&1
    echo "claude exit code: $?" >> "$LOG"
    HOSTS="$HOSTS Claude"
fi

if [ -z "$HOSTS" ]; then
    status NO_HOST "Node.js and the pairing key are ready. No assistant CLI was found"
else
    status DONE "Ready - restart the MCP connection in$HOSTS"
fi

finish
