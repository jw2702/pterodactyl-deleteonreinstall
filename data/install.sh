#!/bin/sh
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MARKER="blueprintframework:deleteonreinstall"

TS_API="$PTERODACTYL_DIRECTORY/resources/scripts/api/server/reinstallServer.ts"
TSX_BOX="$PTERODACTYL_DIRECTORY/resources/scripts/components/server/settings/ReinstallServerBox.tsx"
PHP_REQUEST="$PTERODACTYL_DIRECTORY/app/Http/Requests/Api/Client/Servers/Settings/ReinstallServerRequest.php"
PHP_CONTROLLER="$PTERODACTYL_DIRECTORY/app/Http/Controllers/Api/Client/Servers/SettingsController.php"

patch_file() {
    file="$1"
    if grep -q "$MARKER" "$file"; then
        echo "[deleteonreinstall] $file already patched, skipping."
        return 0
    fi
    return 1
}

# Aborts loudly (instead of silently no-op-ing) when a file this extension
# depends on doesn't look like what it was written against - most likely
# because the installed Pterodactyl panel version changed the source. No
# changes are made to the offending file in that case.
require_anchor() {
    file="$1"
    pattern="$2"
    label="$3"
    if [ ! -f "$file" ]; then
        echo "[deleteonreinstall] FATAL: file not found: $file"
        echo "[deleteonreinstall]   Cannot patch a file that doesn't exist. Aborting."
        exit 1
    fi
    if ! grep -qF -- "$pattern" "$file"; then
        echo "[deleteonreinstall] FATAL: cannot patch $file"
        echo "[deleteonreinstall]   Expected content not found: $label"
        echo "[deleteonreinstall]   This usually means the installed Pterodactyl panel version has"
        echo "[deleteonreinstall]   different source code than this extension's patches expect."
        echo "[deleteonreinstall]   No changes were made to $file. Aborting."
        exit 1
    fi
}

# Confirms a patch step actually produced the expected result, instead of
# silently continuing if a sed substitution quietly failed to match/apply.
verify_result() {
    file="$1"
    pattern="$2"
    label="$3"
    if ! grep -qF -- "$pattern" "$file"; then
        echo "[deleteonreinstall] FATAL: patch verification failed for $file"
        echo "[deleteonreinstall]   Expected result not found after patching: $label"
        echo "[deleteonreinstall]   $file may now be in an inconsistent, half-patched state."
        echo "[deleteonreinstall]   Run 'blueprint -remove deleteonreinstall' to revert, restore the"
        echo "[deleteonreinstall]   file from a clean panel copy if that doesn't fully clean it up,"
        echo "[deleteonreinstall]   then investigate before retrying."
        exit 1
    fi
}

# 1) resources/scripts/api/server/reinstallServer.ts
if ! patch_file "$TS_API"; then
    require_anchor "$TS_API" 'export default (uuid: string): Promise<void> => {' "reinstallServer() function signature"
    require_anchor "$TS_API" 'http.post(`/api/client/servers/${uuid}/settings/reinstall`)' "reinstall API POST call"

    sed -i \
        -e "s/export default (uuid: string): Promise<void> => {/export default (uuid: string, truncate?: boolean): Promise<void> => {/" \
        -e "s|http\\.post(\`/api/client/servers/\${uuid}/settings/reinstall\`)|http.post(\`/api/client/servers/\${uuid}/settings/reinstall\`, { truncate })|" \
        -e "1i // ${MARKER}" \
        "$TS_API"

    verify_result "$TS_API" 'export default (uuid: string, truncate?: boolean): Promise<void> => {' "truncate parameter on function signature"
    verify_result "$TS_API" 'http.post(`/api/client/servers/${uuid}/settings/reinstall`, { truncate })' "truncate in POST body"
    echo "[deleteonreinstall] Patched reinstallServer.ts"
fi

# 2) resources/scripts/components/server/settings/ReinstallServerBox.tsx
if ! patch_file "$TSX_BOX"; then
    require_anchor "$TSX_BOX" "import { Dialog } from '@/components/elements/dialog';" "Dialog import"
    require_anchor "$TSX_BOX" 'const [modalVisible, setModalVisible] = useState(false);' "modalVisible state declaration"
    require_anchor "$TSX_BOX" 'reinstallServer(uuid)' "reinstallServer(uuid) call"
    require_anchor "$TSX_BOX" 'you wish to continue?' "confirmation dialog text"

    sed -i \
        -e "s/import { Dialog } from '@\/components\/elements\/dialog';/import { Dialog } from '@\/components\/elements\/dialog';\nimport Input from '@\/components\/elements\/Input'; \/\/ ${MARKER}/" \
        -e "s/const \[modalVisible, setModalVisible\] = useState(false);/const [modalVisible, setModalVisible] = useState(false);\n    const [truncate, setTruncate] = useState(false); \/\/ ${MARKER}/" \
        -e "s/reinstallServer(uuid)/reinstallServer(uuid, truncate)/" \
        "$TSX_BOX"
    sed -i -f "$SCRIPT_DIR/patches/insert_tsx_checkbox.sed" "$TSX_BOX"

    verify_result "$TSX_BOX" "import Input from '@/components/elements/Input';" "Input component import"
    verify_result "$TSX_BOX" 'const [truncate, setTruncate] = useState(false);' "truncate state declaration"
    verify_result "$TSX_BOX" 'reinstallServer(uuid, truncate)' "truncate passed to reinstallServer()"
    verify_result "$TSX_BOX" "id={'reinstall_truncate'}" "checkbox markup"
    echo "[deleteonreinstall] Patched ReinstallServerBox.tsx"
fi

# 3) app/Http/Requests/Api/Client/Servers/Settings/ReinstallServerRequest.php
if ! patch_file "$PHP_REQUEST"; then
    require_anchor "$PHP_REQUEST" 'public function permission(): string' "permission() method"

    sed -i -f "$SCRIPT_DIR/patches/insert_php_request_rules.sed" "$PHP_REQUEST"

    verify_result "$PHP_REQUEST" 'public function rules(): array' "rules() method"
    verify_result "$PHP_REQUEST" "'truncate' => 'sometimes|boolean'," "truncate validation rule"
    echo "[deleteonreinstall] Patched ReinstallServerRequest.php"
fi

# 4) app/Http/Controllers/Api/Client/Servers/SettingsController.php
if ! patch_file "$PHP_CONTROLLER"; then
    require_anchor "$PHP_CONTROLLER" 'use Pterodactyl\Repositories\Eloquent\ServerRepository;' "ServerRepository use-import"
    require_anchor "$PHP_CONTROLLER" 'private ReinstallServerService $reinstallServerService,' "constructor parameter"
    require_anchor "$PHP_CONTROLLER" '$this->reinstallServerService->handle($server);' "reinstall() method body"

    sed -i -f "$SCRIPT_DIR/patches/insert_php_controller.sed" "$PHP_CONTROLLER"

    verify_result "$PHP_CONTROLLER" 'use Pterodactyl\Repositories\Wings\DaemonFileRepository;' "DaemonFileRepository use-import"
    verify_result "$PHP_CONTROLLER" 'private DaemonFileRepository $daemonFileRepository,' "constructor parameter"
    verify_result "$PHP_CONTROLLER" "if (\$request->boolean('truncate')) {" "truncate check in reinstall()"
    echo "[deleteonreinstall] Patched SettingsController.php"
fi

echo "[deleteonreinstall] Done. Blueprint will rebuild frontend assets and cache automatically."
