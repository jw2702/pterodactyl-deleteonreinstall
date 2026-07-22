# deleteonreinstall

Blueprint-Extension für [Pterodactyl](https://pterodactyl.io), die dem
"Confirm server reinstallation"-Dialog unter `/server/:id/settings`
(Button "Reinstall Server") eine Checkbox **"Delete all files before
reinstalling."** hinzufügt — analog zur bereits existierenden
"Delete all files before restoring backup."-Option beim Wiederherstellen
eines Backups (`resources/scripts/components/server/backups/BackupContextMenu.tsx`).

## Funktionsweise

Blueprints `Components.yml` erlaubt nur das Einhängen zusätzlicher React-Komponenten
in vordefinierte Slots (z. B. `Server.Settings.BeforeContent`/`AfterContent`), aber keine
Änderung an bereits bestehenden Panel-Komponenten wie der nativen
`ReinstallServerBox.tsx`. Da hier explizit der *native* Dialog erweitert werden soll,
patcht diese Extension die betroffenen Panel-Dateien direkt per `sed`
(so wie es die [Extension-scripts-Doku](https://blueprint.zip/docs/concepts/scripts)
für "out-of-scope"-Änderungen vorsieht) — die Skripte fügen nur klar durch
`blueprintframework:deleteonreinstall`-Marker gekennzeichnete Zeilen/Blöcke ein
und lassen sich dadurch beim Entfernen der Extension exakt wieder rückgängig machen.

Patched werden:

- `resources/scripts/api/server/reinstallServer.ts` — nimmt jetzt einen zweiten
  `truncate`-Parameter entgegen und schickt ihn im Request-Body mit.
- `resources/scripts/components/server/settings/ReinstallServerBox.tsx` — fügt die
  Checkbox in den bestehenden `Dialog.Confirm` ein (gleiche Optik/Klassen wie beim
  Backup-Restore-Dialog).
- `app/Http/Requests/Api/Client/Servers/Settings/ReinstallServerRequest.php` —
  validiert das neue `truncate`-Feld (`sometimes|boolean`).
- `app/Http/Controllers/Api/Client/Servers/SettingsController.php` — wenn `truncate`
  gesetzt ist, werden vor dem eigentlichen Reinstall alle Dateien im Server-Root über
  Wings (`DaemonFileRepository::getDirectory()` + `::deleteFiles()`) gelöscht — genau
  der Mechanismus, den Wings/Panel auch beim `truncate_directory`-Flag der
  Backup-Wiederherstellung nutzen. Der Wings-`reinstall`-Endpunkt selbst unterstützt
  kein Truncate-Flag, daher übernimmt der Panel-Controller das Löschen vorab.

### Warum `data/` + `data.directory: "data"`

Laut [Extension-scripts-Doku](https://blueprint.zip/docs/concepts/scripts) müssen
`install.sh`/`update.sh`/`remove.sh` im Wurzelpfad des über `data.directory` gebundenen
Ordners liegen. Blueprint kopiert diesen Ordner nach
`.blueprint/extensions/<identifier>/private/` und sucht **dort** — und nur dort — nach
den Skripten (bestätigt im Blueprint-Quellcode, `scripts/commands/extensions/remove.sh`).
Ohne diese Bindung wird v. a. `remove.sh` beim Entfernen der Extension stillschweigend
**nicht** ausgeführt, die Patches an den Panel-Dateien bleiben also bestehen. Deshalb
liegen `install.sh`, `update.sh`, `remove.sh` und `patches/` hier unter `data/`, gebunden
über `data.directory: "data"` in der `conf.yml`.

### Warum `components/Components.yml` (ohne echte Komponenten)

Blueprint löst einen Frontend-Rebuild (`yarn build:production`) nur aus, wenn die
Extension `dashboard.css`, `dashboard.wrapper` oder `dashboard.components` bindet.
Da wir den nativen Panel-Code direkt patchen (nicht über die Components-API), bräuchten
wir eigentlich keine `Components.yml` — binden aber trotzdem eine (funktional leere)
`components/`-Directory, damit Blueprint nach dem `install.sh`/`remove.sh`-Lauf
zuverlässig neu baut. Die Datei muss mindestens einen echten YAML-Key enthalten
(nicht nur Kommentare oder `{}`) — Blueprints eigener `parse_yaml`-Bash-Parser erzeugt bei
komplett leerem Inhalt sonst einen fehlerhaften `eval`-Aufruf (`={}: command not found`).

## Installation (Entwicklung)

```bash
# Developer-Modus im Admin-Panel unter /admin/extensions aktivieren, dann:
rm -rf /var/www/pterodactyl/.blueprint/dev/*
cp -r deleteonreinstall/* /var/www/pterodactyl/.blueprint/dev/
cd /var/www/pterodactyl
blueprint -build
```

`.blueprint/dev` ist bei Blueprint immer flach (eine Extension pro Dev-Ordner) — die
Dateien kommen direkt hinein, nicht in einen weiteren `deleteonreinstall/`-Unterordner.

## Deinstallation

```bash
blueprint -remove deleteonreinstall
```

`remove.sh` macht alle vier Patches exakt rückgängig (per Marker-Blöcken), unabhängig
davon, ob die Extension zuvor über `install.sh` oder `update.sh` installiert wurde.

### Verifikation statt Annahme

`install.sh` prüft vor jedem Patch-Schritt per `require_anchor`, ob die erwartete
Original-Textstelle noch existiert, und danach per `verify_result`, ob die Änderung
tatsächlich angekommen ist. `remove.sh` prüft nach dem Revert ebenso (`verify_result` +
`verify_no_marker`). Passt eine Panel-Version nicht mehr zu den `sed`-Patches (z. B. nach
einem Pterodactyl-Update mit geändertem Quellcode), bricht das Skript mit einer klaren
`FATAL`-Meldung ab, statt still nichts zu tun oder eine Datei halb gepatcht zu
hinterlassen — geprüft mit einem simulierten Anker-Mismatch (siehe Testreihe unten).

### Bekannte Blueprint-Einschränkung: `update.sh`

Laut Doku führt Blueprint beim Aktualisieren einer bereits installierten Extension
**nicht** das `update.sh` der neuen Version aus, sondern das `update.sh`, das von der
zuvor installierten Version in `private/` liegt. Ändert sich `update.sh`/`install.sh`
zwischen zwei Versionen dieser Extension, reicht ein einfaches erneutes `blueprint
-build` also nicht zuverlässig aus, um die neuen Skripte zu übernehmen. Bei
Skript-Änderungen daher immer einmal komplett neu aufsetzen:

```bash
blueprint -remove deleteonreinstall
blueprint -build
```

(Reine Patch-Inhaltsänderungen — z. B. an den `.sed`-Dateien ohne `install.sh`/
`update.sh` selbst zu ändern — sind davon nicht betroffen, da diese immer frisch aus
`private/` gelesen werden.)

## Testen ohne Panel

Die `data/patches/*.sed`-Skripte lassen sich isoliert gegen Kopien der vier
Original-Dateien testen (`install.sh` prüft per Marker, ob eine Datei schon gepatcht ist,
und überspringt sie dann; `remove.sh` prüft ebenso und ist ein No-Op auf ungepatchten
Dateien). Beide Skripte sind bewusst POSIX-`sh`-kompatibel gehalten (kein
`${BASH_SOURCE[0]}`, kein `local`) und wurden sowohl unter `bash` als auch unter `dash`
getestet.

## Kompatibilität

Zuletzt verifiziert gegen:

- Pterodactyl Panel: `develop`-Branch (Stand: siehe Datum dieses Commits) — die vier
  gepatchten Dateien wurden 1:1 mit dem aktuellen Upstream-Quellcode abgeglichen.
- Blueprint Framework: `beta-2026-06` (aktuelles stabiles Release, passend zu
  `info.target` in `conf.yml`).

Da die Patches auf exakten Textstellen im Panel-Quellcode basieren, ist Kompatibilität
mit *zukünftigen* Pterodactyl-Versionen nicht garantiert — wird aber, dank der
Verifikation oben, im Fehlerfall immer laut und mit klarer Fehlermeldung erkannt statt
unbemerkt zu einer wirkungslosen Installation zu führen.
