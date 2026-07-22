#!/bin/sh
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# install.sh is idempotent (guarded by marker checks), so updates simply
# re-run it in case the patched core files changed between Pterodactyl versions.
sh "$SCRIPT_DIR/install.sh"
