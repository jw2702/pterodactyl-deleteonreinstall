# deleteonreinstall

A Blueprint extension for [Pterodactyl](https://pterodactyl.io) that adds a
**"Delete all files before reinstalling."** checkbox to the "Confirm server
reinstallation" dialog under `/server/:id/settings` (the "Reinstall Server"
button) — mirroring the existing "Delete all files before restoring backup."
option available when restoring a backup
(`resources/scripts/components/server/backups/BackupContextMenu.tsx`).

## How it works

Blueprint's `Components.yml` only allows mounting additional React components
into predefined slots (e.g. `Server.Settings.BeforeContent`/`AfterContent`),
not modifying existing panel components such as the native
`ReinstallServerBox.tsx`. Since this extension needs to extend the *native*
dialog itself, it patches the affected panel files directly via `sed` (as
described in the [extension scripts docs](https://blueprint.zip/docs/concepts/scripts)
for "out-of-scope" changes) — the scripts only insert lines/blocks clearly
marked with `blueprintframework:deleteonreinstall` markers, so they can be
reverted exactly when the extension is removed.

Files patched:

- `resources/scripts/api/server/reinstallServer.ts` — now accepts a second
  `truncate` parameter and sends it in the request body.
- `resources/scripts/components/server/settings/ReinstallServerBox.tsx` —
  adds the checkbox to the existing `Dialog.Confirm` (same look/classes as
  the backup restore dialog).
- `app/Http/Requests/Api/Client/Servers/Settings/ReinstallServerRequest.php`
  — validates the new `truncate` field (`sometimes|boolean`).
- `app/Http/Controllers/Api/Client/Servers/SettingsController.php` — when
  `truncate` is set, all files in the server root are deleted via Wings
  (`DaemonFileRepository::getDirectory()` + `::deleteFiles()`) before the
  actual reinstall — the same mechanism Wings/Panel use for the
  `truncate_directory` flag during backup restoration. The Wings `reinstall`
  endpoint itself has no truncate flag, so the panel controller handles the
  deletion upfront.

### Why `data/` + `data.directory: "data"`

Per the [extension scripts docs](https://blueprint.zip/docs/concepts/scripts),
`install.sh`/`update.sh`/`remove.sh` must live at the root of the folder
bound via `data.directory`. Blueprint copies that folder to
`.blueprint/extensions/<identifier>/private/` and looks for the scripts
**only** there (confirmed in Blueprint's source, `scripts/commands/extensions/remove.sh`).
Without this binding, `remove.sh` in particular is silently **not** executed
when the extension is removed, leaving the patches to the panel files in
place. That's why `install.sh`, `update.sh`, `remove.sh`, and `patches/`
live under `data/`, bound via `data.directory: "data"` in `conf.yml`.

### Why `components/Components.yml` (with no real components)

Blueprint only triggers a frontend rebuild (`yarn build:production`) if the
extension binds `dashboard.css`, `dashboard.wrapper`, or
`dashboard.components`. Since we patch the native panel code directly
(rather than going through the Components API), a `Components.yml` isn't
strictly needed — but we bind a (functionally empty) `components/` directory
anyway so Blueprint reliably rebuilds after `install.sh`/`remove.sh` runs.
The file must contain at least one real YAML key (not just comments or
`{}`) — Blueprint's own `parse_yaml` bash parser otherwise produces a broken
`eval` call (`={}: command not found`) on completely empty content.

## Installation

1. Download the latest `deleteonreinstall.blueprint` file from the
   [Releases](https://github.com/jw2702/pterodactyl-deleteonreinstall/releases) page.
2. Upload it to your panel and run:

   ```bash
   blueprint -install deleteonreinstall.blueprint
   ```

## Uninstallation

```bash
blueprint -remove deleteonreinstall
```

`remove.sh` reverts all four patches exactly (via marker blocks), regardless
of whether the extension was previously installed via `install.sh` or
`update.sh`.

### Verification instead of assumption

Before each patch step, `install.sh` checks via `require_anchor` whether the
expected original text still exists, and afterwards via `verify_result`
whether the change actually landed. `remove.sh` performs the same checks
after reverting (`verify_result` + `verify_no_marker`). If a panel version no
longer matches the `sed` patches (e.g. after a Pterodactyl update changed
the source code), the script aborts with a clear `FATAL` message instead of
silently doing nothing or leaving a file half-patched — verified with a
simulated anchor mismatch (see the test section below).

### Known Blueprint limitation: `update.sh`

Per the docs, when updating an already-installed extension, Blueprint does
**not** run the `update.sh` of the new version, but the `update.sh` that was
left in `private/` by the previously installed version. If `update.sh`/
`install.sh` changes between two versions of this extension, a simple
`blueprint -build` is therefore not reliably enough to pick up the new
scripts. When the scripts themselves change, always do a full reinstall:

```bash
blueprint -remove deleteonreinstall
blueprint -build
```

(Pure patch-content changes — e.g. to the `.sed` files without changing
`install.sh`/`update.sh` themselves — aren't affected, since those are
always read fresh from `private/`.)

## Testing without a panel

The `data/patches/*.sed` scripts can be tested in isolation against copies
of the four original files (`install.sh` checks via markers whether a file
is already patched and skips it if so; `remove.sh` does the same check and
is a no-op on unpatched files). Both scripts are deliberately kept
POSIX-`sh` compatible (no `${BASH_SOURCE[0]}`, no `local`) and have been
tested under both `bash` and `dash`.

## Compatibility

Last verified against:

- Pterodactyl Panel: `develop` branch (as of the date of this commit) — the
  four patched files were compared 1:1 against the current upstream source.
- Blueprint Framework: `beta-2026-06` (current stable release, matching
  `info.target` in `conf.yml`).

Since the patches rely on exact text locations in the panel source code,
compatibility with *future* Pterodactyl versions is not guaranteed — but
thanks to the verification described above, any mismatch will always be
caught loudly with a clear error message rather than silently resulting in
a no-op installation.
