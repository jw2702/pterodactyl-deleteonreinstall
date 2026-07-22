#!/bin/sh
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MARKER="blueprintframework:deleteonreinstall"

TS_API="$PTERODACTYL_DIRECTORY/resources/scripts/api/server/reinstallServer.ts"
TSX_BOX="$PTERODACTYL_DIRECTORY/resources/scripts/components/server/settings/ReinstallServerBox.tsx"
PHP_REQUEST="$PTERODACTYL_DIRECTORY/app/Http/Requests/Api/Client/Servers/Settings/ReinstallServerRequest.php"
PHP_CONTROLLER="$PTERODACTYL_DIRECTORY/app/Http/Controllers/Api/Client/Servers/SettingsController.php"

unpatch_file() {
    file="$1"
    if [ ! -f "$file" ] || ! grep -q "$MARKER" "$file"; then
        echo "[deleteonreinstall] $file not patched (or missing), skipping."
        return 1
    fi
    return 0
}

# Confirms a revert step actually produced the expected (original) result,
# instead of silently continuing if a sed substitution quietly failed to
# match/apply - e.g. because the file was hand-edited after installing.
verify_result() {
    file="$1"
    pattern="$2"
    label="$3"
    if ! grep -qF -- "$pattern" "$file"; then
        echo "[deleteonreinstall] FATAL: revert verification failed for $file"
        echo "[deleteonreinstall]   Expected original content not found after reverting: $label"
        echo "[deleteonreinstall]   $file may now be in an inconsistent, half-reverted state."
        echo "[deleteonreinstall]   Compare it against a clean copy of this Pterodactyl version and"
        echo "[deleteonreinstall]   fix it by hand before reinstalling this extension."
        exit 1
    fi
}

# Confirms no trace of this extension's markers is left in the file.
verify_no_marker() {
    file="$1"
    if grep -q "$MARKER" "$file"; then
        echo "[deleteonreinstall] FATAL: $file still contains '$MARKER' after reverting."
        echo "[deleteonreinstall]   Aborting so this doesn't go unnoticed - please inspect the file by hand."
        exit 1
    fi
}

# 1) resources/scripts/api/server/reinstallServer.ts
if unpatch_file "$TS_API"; then
    sed -i -f "$SCRIPT_DIR/patches/remove_blocks.sed" "$TS_API"
    sed -i \
        -e "s/export default (uuid: string, truncate?: boolean): Promise<void> => {/export default (uuid: string): Promise<void> => {/" \
        -e "s|http\\.post(\`/api/client/servers/\${uuid}/settings/reinstall\`, { truncate })|http.post(\`/api/client/servers/\${uuid}/settings/reinstall\`)|" \
        "$TS_API"

    verify_result "$TS_API" 'export default (uuid: string): Promise<void> => {' "original function signature"
    verify_result "$TS_API" 'http.post(`/api/client/servers/${uuid}/settings/reinstall`)' "original POST call"
    verify_no_marker "$TS_API"
    echo "[deleteonreinstall] Reverted reinstallServer.ts"
fi

# 2) resources/scripts/components/server/settings/ReinstallServerBox.tsx
if unpatch_file "$TSX_BOX"; then
    sed -i -f "$SCRIPT_DIR/patches/remove_blocks.sed" "$TSX_BOX"
    sed -i -e "s/reinstallServer(uuid, truncate)/reinstallServer(uuid)/" "$TSX_BOX"

    verify_result "$TSX_BOX" 'reinstallServer(uuid)' "original reinstallServer() call"
    verify_no_marker "$TSX_BOX"
    echo "[deleteonreinstall] Reverted ReinstallServerBox.tsx"
fi

# 3) app/Http/Requests/Api/Client/Servers/Settings/ReinstallServerRequest.php
if unpatch_file "$PHP_REQUEST"; then
    sed -i -f "$SCRIPT_DIR/patches/remove_blocks.sed" "$PHP_REQUEST"

    verify_no_marker "$PHP_REQUEST"
    echo "[deleteonreinstall] Reverted ReinstallServerRequest.php"
fi

# 4) app/Http/Controllers/Api/Client/Servers/SettingsController.php
if unpatch_file "$PHP_CONTROLLER"; then
    sed -i -f "$SCRIPT_DIR/patches/remove_blocks.sed" "$PHP_CONTROLLER"

    verify_no_marker "$PHP_CONTROLLER"
    echo "[deleteonreinstall] Reverted SettingsController.php"
fi

echo "[deleteonreinstall] Done. Blueprint will rebuild frontend assets and cache automatically."
