#!/bin/zsh
# Zentrale Konfiguration für init_macsafe.sh und macsafe.sh
# Wird per "source" eingebunden – nicht direkt ausführen.

BACKUP_DIR="$HOME/backups"
VAULT_PATH="$BACKUP_DIR/macsafe.sparseimage"
VAULT_SIZE="10g"
VOLUME_NAME="Macsafe"
MOUNT_POINT="/Volumes/$VOLUME_NAME"

KEYCHAIN_ACCOUNT="macsafe_backup"
KEYCHAIN_SERVICE="MacsafeVaultPassword"

# Datei mit den zu sichernden Verzeichnissen (eine Zeile pro Verzeichnis)
SOURCES_FILE="${0:A:h}/macsafe_sources.conf"

# Anzahl der aufzubewahrenden Snapshots (0 = unbegrenzt)
KEEP_SNAPSHOTS=30
