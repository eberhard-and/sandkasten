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

mkdir -p "${LOG_FILE:h}"
ERR_TMP=$(mktemp -t macsafe) || exit 1
trap 'rm -f "$ERR_TMP"' EXIT

# Zeile mit Zeitstempel ins Log und auf die Konsole schreiben
log() {
    local line="$(date '+%Y-%m-%d %H:%M:%S') $*"
    print -r -- "$line"
    print -r -- "$line" >> "$LOG_FILE"
}
log_error() {
    local line="$(date '+%Y-%m-%d %H:%M:%S') FEHLER: $*"
    print -r -- "$line" >&2
    print -r -- "$line" >> "$LOG_FILE"
}
# Inhalt von $ERR_TMP (stderr eines Befehls) zeilenweise als Fehler protokollieren
log_error_output() {
    local l
    while IFS= read -r l; do
        [[ -n "$l" ]] && log_error "  $l"
    done < "$ERR_TMP"
}
fail() {
    log_error "$*"
    exit 1
}

log "Backup gestartet"

# Quellverzeichnisse aus Konfig-Datei lesen
[[ -r "$SOURCES_FILE" ]] || fail "Konfig-Datei $SOURCES_FILE nicht lesbar"
SOURCES=()
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%\#*}"                                  # Kommentare entfernen
    line="${${line##[[:space:]]#}%%[[:space:]]#}"        # trimmen
    [[ -z "$line" ]] && continue
    # Pfad unverändert verwenden; falls nicht vorhanden, Quoting ("..", '..', \ ) entfernen
    dir="${line/#\~/$HOME}"
    if [[ ! -d "$dir" ]]; then
        dir="${(Q)line}"
        dir="${dir/#\~/$HOME}"
    fi
    if [[ -d "$dir" ]]; then
        SOURCES+=("$dir")
    else
        log "WARNUNG: $line existiert nicht – übersprungen"
    fi
done < "$SOURCES_FILE"

(( ${#SOURCES} > 0 )) || fail "keine gültigen Verzeichnisse in $SOURCES_FILE"

# Passwort aus Keychain
PASSWORD=$(security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)
[[ -n "$PASSWORD" ]] || fail "Passwort nicht in Keychain gefunden"

# Mounten (falls nicht bereits gemountet)
if [[ ! -d "$MOUNT_POINT" ]]; then
    printf '%s' "$PASSWORD" | hdiutil attach "$VAULT_PATH" -stdinpass -nobrowse >/dev/null 2>"$ERR_TMP"
fi
unset PASSWORD

if [[ ! -d "$MOUNT_POINT" ]]; then
    log_error_output
    fail "Mount von $VAULT_PATH fehlgeschlagen"
fi

SNAP_ROOT="$MOUNT_POINT/snapshots"
DEST="$SNAP_ROOT/$(date +%Y-%m-%d_%H%M%S)"
LATEST="$SNAP_ROOT/latest"
mkdir -p "$SNAP_ROOT"

LINK_OPT=()
[[ -d "$LATEST" ]] && LINK_OPT=(--link-dest="${LATEST:A}")

# -R: vollständigen Pfad übernehmen (verhindert Kollisionen gleichnamiger Verzeichnisse)
STATS=$(rsync -aR --stats "${LINK_OPT[@]}" "${SOURCES[@]}" "$DEST/" 2>"$ERR_TMP")
RSYNC_RC=$?
if (( RSYNC_RC == 0 )); then
    ln -sfn "${DEST:t}" "$LATEST"
    # "Number of files transferred" (openrsync) bzw. "Number of regular files transferred" (GNU rsync)
    COPIED=$(print -r -- "$STATS" | sed -n 's/^Number of .*files transferred: *//p' | tr -d ',.' | head -1)
    log "Snapshot ${DEST:t} erstellt – ${COPIED:-?} Datei(en) kopiert"
    RC=0
else
    log_error_output
    log_error "rsync fehlgeschlagen (Exit-Code $RSYNC_RC) – unvollständiger Snapshot wird entfernt"
    rm -rf "$DEST"
    RC=1
fi

# Alte Snapshots aufräumen
if (( RC == 0 && KEEP_SNAPSHOTS > 0 )); then
    snaps=("$SNAP_ROOT"/<->-<->-<->_<->(N/On))           # neueste zuerst
    for old in "${snaps[@]:$KEEP_SNAPSHOTS}"; do
        rm -rf "$old" && log "alter Snapshot ${old:t} gelöscht"
    done
fi

if ! hdiutil detach "$MOUNT_POINT" >/dev/null 2>"$ERR_TMP"; then
    log_error_output
    log_error "Detach von $MOUNT_POINT fehlgeschlagen"
fi

if (( RC == 0 )); then
    log "Backup erfolgreich abgeschlossen"
else
    log_error "Backup mit Fehlern beendet"
fi
exit $RC
