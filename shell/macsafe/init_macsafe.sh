#!/bin/zsh
# Einmalige Einrichtung: verschlüsseltes Image anlegen und Passwort in der Keychain ablegen.

source "${0:A:h}/vars.sh" || { echo "Fehler: vars.sh nicht gefunden" >&2; exit 1; }

if [[ -e "$VAULT_PATH" ]]; then
    echo "Fehler: $VAULT_PATH existiert bereits" >&2
    exit 1
fi

read -s "PASSWORD?Passwort für das Image: "; echo
read -s "PASSWORD2?Passwort wiederholen: "; echo
if [[ -z "$PASSWORD" || "$PASSWORD" != "$PASSWORD2" ]]; then
    echo "Fehler: Passwörter leer oder nicht identisch" >&2
    exit 1
fi
unset PASSWORD2

# Backup-Verzeichnis anlegen
mkdir -p "$BACKUP_DIR"

# Image anlegen (Passwort über stdin, nicht über die Kommandozeile)
printf '%s' "$PASSWORD" | hdiutil create -size "$VAULT_SIZE" -type SPARSE -fs APFS \
    -encryption AES-256 -stdinpass -volname "$VOLUME_NAME" "$VAULT_PATH" \
    || { echo "Fehler: Image konnte nicht angelegt werden" >&2; exit 1; }

# Passwort in Keychain ablegen (-U: vorhandenen Eintrag aktualisieren)
security add-generic-password -U -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" \
    -D "encrypted backup" -w "$PASSWORD" \
    || { echo "Fehler: Keychain-Eintrag fehlgeschlagen" >&2; exit 1; }
unset PASSWORD

# Test
if security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
    echo "✓ Image $VAULT_PATH angelegt, Passwort in Keychain gespeichert"
else
    echo "✗ Passwort nicht in Keychain gefunden" >&2
    exit 1
fi
