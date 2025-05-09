#!/bin/bash

# === Configuration ===
ALIAS_NAME="minio"
BACKUP_DIR="./minio_backup_admin"
DATA_BACKUP_DIR="$BACKUP_DIR/buckets"
DATA_BACKUP_DIR_ARCHIVES="./backup_archives"
TIMESTAMP=$(date +%F_%H-%M)
LOG_FILE="$DATA_BACKUP_DIR_ARCHIVES/minio_backup_log_$TIMESTAMP.log"
ARCHIVE_FILE="minio_backup_$TIMESTAMP.tar.gz"

# === Initialisation ===
mkdir -p "$BACKUP_DIR/users" "$BACKUP_DIR/groups" "$BACKUP_DIR/policies" "$BACKUP_DIR/service-accounts" "$DATA_BACKUP_DIR" "$DATA_BACKUP_DIR_ARCHIVES"

# === Lancement du log ===
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📅 Démarrage de la sauvegarde MinIO - $TIMESTAMP"
echo "📁 Dossier de sauvegarde : $BACKUP_DIR"
echo "📝 Log sauvegardé dans : $LOG_FILE"
echo "----------------------------"

echo "🔐 Récupération des utilisateurs..."
mc admin user list $ALIAS_NAME | awk '{print $2}' | grep -v Username | while read -r user; do
    safe_user=$(echo "$user" | tr '/ ' '_')
    echo "- Export user: $user"
    mc admin user info $ALIAS_NAME "$user" > "$BACKUP_DIR/users/${safe_user}.info"
done

echo "👥 Récupération des groupes..."
mc admin group list $ALIAS_NAME | awk '{print $1}' | grep -v Group | while read -r group; do
    safe_group=$(echo "$group" | tr '/ ' '_')
    echo "- Export group: $group"
    mc admin group info $ALIAS_NAME "$group" > "$BACKUP_DIR/groups/${safe_group}.info"
done

echo "📜 Récupération des policies..."
mc admin policy list $ALIAS_NAME | awk '{print $1}' | grep -v Policy | while read -r policy; do
    safe_policy=$(echo "$policy" | tr '/ ' '_')
    echo "- Export policy: $policy"
    mc admin policy info $ALIAS_NAME "$policy" > "$BACKUP_DIR/policies/${safe_policy}.json"
done

echo "🔑 Récupération des service accounts (tokens)..."
mc admin user svcacct list $ALIAS_NAME | jq -r '.[] | .user + ":" + .accessKey' | while IFS=":" read -r user access_key; do
    safe_user=$(echo "$user" | tr '/ ' '_')
    safe_key=$(echo "$access_key" | tr '/ ' '_')
    echo "- Export service account for user: $user (access: $access_key)"
    mc admin user svcacct info $ALIAS_NAME "$access_key" > "$BACKUP_DIR/service-accounts/${safe_user}_${safe_key}.info"
done

echo "🗂️  Récupération des buckets..."
mc ls $ALIAS_NAME | awk '{print $5}' | while read -r bucket; do
    echo "- Sauvegarde du bucket: $bucket"
    mc mirror --overwrite "$ALIAS_NAME/$bucket" "$DATA_BACKUP_DIR/$bucket"
done

echo "📦 Compression de la sauvegarde..."
tar -czf "$DATA_BACKUP_DIR_ARCHIVES/$ARCHIVE_FILE" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
echo "🗃️  Archive créée : $DATA_BACKUP_DIR_ARCHIVES/$ARCHIVE_FILE"

# === Nettoyage des backups de +7 jours ===
echo "🧹 Rotation des sauvegardes (fichiers de plus de 7 jours)..."
find "$DATA_BACKUP_DIR_ARCHIVES" -name "minio_backup_*.tar.gz" -type f -mtime +7 -exec rm -v {} \;
find "$DATA_BACKUP_DIR_ARCHIVES" -name "minio_backup_log_*.log" -type f -mtime +7 -exec rm -v {} \;

echo "✅ Sauvegarde complète terminée et rotation effectuée."
