#!/bin/zsh
# Inkrementelles Snapshot-Backup in das verschlüsselte Image.
# Jeder Lauf erzeugt snapshots/<Zeitstempel>/ mit vollständigem Stand;
# unveränderte Dateien werden per Hardlink auf den vorherigen Snapshot
# referenziert (belegen keinen zusätzlichen Platz),
# - geänderte Dateien werden neu gespeichert
# – alte Versionen bleiben im älteren Snapshot erhalten.
# - Schlägt rsync fehl, wird der unvollständige Snapshot wieder entfernt.
#
# Hinweis: Für den kurzen Moment, in dem das Passwort in der Keychain abgelegt wird,
# ist es in der Prozessliste sichtbar.


source "${0:A:h}/vars.sh" || { echo "Fehler: vars.sh nicht gefunden" >&2; exit 1; }
setopt extended_glob

# Quellverzeichnisse aus Konfig-Datei lesen
if [[ ! -r "$SOURCES_FILE" ]]; then
    echo "Fehler: Konfig-Datei $SOURCES_FILE nicht lesbar" >&2
    exit 1
fi
SOURCES=()
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%\#*}"                                  # Kommentare entfernen
    line="${${line##[[:space:]]#}%%[[:space:]]#}"        # trimmen
    [[ -z "$line" ]] && continue
    line="${line/#\~/$HOME}"
    if [[ -d "$line" ]]; then
        SOURCES+=("$line")
    else
        echo "Warnung: $line existiert nicht – übersprungen" >&2
    fi
done < "$SOURCES_FILE"

if (( ${#SOURCES} == 0 )); then
    echo "Fehler: keine gültigen Verzeichnisse in $SOURCES_FILE" >&2
    exit 1
fi

# Passwort aus Keychain
PASSWORD=$(security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)
if [[ -z "$PASSWORD" ]]; then
    echo "Fehler: Passwort nicht in Keychain gefunden" >&2
    exit 1
fi

# Mounten (falls nicht bereits gemountet)
if [[ ! -d "$MOUNT_POINT" ]]; then
    printf '%s' "$PASSWORD" | hdiutil attach "$VAULT_PATH" -stdinpass -nobrowse >/dev/null
fi
unset PASSWORD

if [[ ! -d "$MOUNT_POINT" ]]; then
    echo "✗ Mount fehlgeschlagen" >&2
    exit 1
fi
echo "✓ Image gemountet"

SNAP_ROOT="$MOUNT_POINT/snapshots"
DEST="$SNAP_ROOT/$(date +%Y-%m-%d_%H%M%S)"
LATEST="$SNAP_ROOT/latest"
mkdir -p "$SNAP_ROOT"

LINK_OPT=()
[[ -d "$LATEST" ]] && LINK_OPT=(--link-dest="${LATEST:A}")

# -R: vollständigen Pfad übernehmen (verhindert Kollisionen gleichnamiger Verzeichnisse)
if rsync -aR "${LINK_OPT[@]}" "${SOURCES[@]}" "$DEST/"; then
    ln -sfn "${DEST:t}" "$LATEST"
    echo "✓ Snapshot ${DEST:t} erstellt"
    RC=0
else
    echo "✗ rsync fehlgeschlagen – unvollständiger Snapshot wird entfernt" >&2
    rm -rf "$DEST"
    RC=1
fi

# Alte Snapshots aufräumen
if (( RC == 0 && KEEP_SNAPSHOTS > 0 )); then
    snaps=("$SNAP_ROOT"/<->-<->-<->_<->(N/On))           # neueste zuerst
    for old in "${snaps[@]:$KEEP_SNAPSHOTS}"; do
        rm -rf "$old" && echo "  alter Snapshot ${old:t} gelöscht"
    done
fi

hdiutil detach "$MOUNT_POINT" >/dev/null || echo "Warnung: Detach fehlgeschlagen" >&2

(( RC == 0 )) && echo "Backup abgeschlossen"
exit $RC
