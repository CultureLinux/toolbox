#!/bin/bash

# === CONFIGURATION ===
ALIAS_NAME="minio"
ARCHIVE_DIR="./backup_archives"
TMP_RESTORE_DIR="./tmp_restore_minio"

# === 1. LISTE LES ARCHIVES DISPONIBLES ===
echo "📦 Archives disponibles dans $ARCHIVE_DIR :"
select archive in "$ARCHIVE_DIR"/minio_backup_*.tar.gz; do
    if [[ -n "$archive" ]]; then
        echo "✅ Archive sélectionnée : $archive"
        break
    else
        echo "❌ Choix invalide. Réessaye."
    fi
done

# === 2. EXTRACTION DE L'ARCHIVE ===
echo "📂 Extraction de l'archive dans $TMP_RESTORE_DIR..."
rm -rf "$TMP_RESTORE_DIR"
mkdir -p "$TMP_RESTORE_DIR"
tar -xzf "$archive" -C "$TMP_RESTORE_DIR"

# === 3. DÉTECTION DU DOSSIER DE BACKUP ===
BACKUP_DIR=$(find "$TMP_RESTORE_DIR" -maxdepth 1 -type d -name "minio_backup_admin")
if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Dossier de backup 'minio_backup_admin' non trouvé après extraction."
    exit 1
fi

DATA_BACKUP_DIR="$BACKUP_DIR/buckets"

echo "♻️ Début de la restauration depuis : $BACKUP_DIR"

# === 4. RESTAURATION DES POLICIES ===
echo "📜 Restauration des policies (avec suppression de toutes les occurrences du champ 'Version')..."
for file in "$BACKUP_DIR/policies/"*.json; do
    policy_name=$(basename "$file" .json)
    echo "- Nettoyage et import de la policy: $policy_name"
    
    # Nettoyage et suppression de toutes les occurrences du champ 'Version'
    cleaned_policy="/tmp/${policy_name}_cleaned.json"
    jq '{
  Version: .Policy.Version,
  Statement: .Policy.Statement
}' "$file" > "$cleaned_policy" || { echo "❌ Erreur dans le fichier $file"; continue; }
    
    # Importation de la policy
    mc admin policy create $ALIAS_NAME "$policy_name" "$cleaned_policy" 
    rm -f "$cleaned_policy"
done


# === 5. RESTAURATION DES UTILISATEURS ===
echo "🔐 Restauration des utilisateurs..."
for file in "$BACKUP_DIR/users/"*.info; do
    user=$(basename "$file" .info)
    password="restore-$(openssl rand -hex 6)"
    echo "- Création de l'utilisateur: $user (mot de passe temporaire: $password)"
    mc admin user add $ALIAS_NAME "$user" "$password"

    # Nom de la policy basée sur la règle de nommage USER-policy
    policy="${user}-policy"

    # Vérification si la policy existe avant de l'attacher
    if mc admin policy info $ALIAS_NAME "$policy" > /dev/null 2>&1; then
        echo "  ↪️ Attache la policy : $policy"
        mc admin policy attach $ALIAS_NAME "$policy" --user "$user"
    else
        echo "  ⚠️ La policy $policy n'existe pas pour l'utilisateur $user"
    fi
done


# === 6. RESTAURATION DES GROUPES ===
echo "👥 Restauration des groupes..."
for file in "$BACKUP_DIR/groups/"*.info; do
    group=$(basename "$file" .info)
    echo "- Import group: $group"
    members=$(grep 'Members:' "$file" | awk -F': ' '{print $2}')
    for user in $members; do
        echo "  ↪️ Ajout de $user au groupe $group"
        mc admin group add $ALIAS_NAME "$group" "$user"
    done
done

# === 7. RESTAURATION DES BUCKETS ===
echo "🗂️  Restauration des buckets et de leurs données..."
for dir in "$DATA_BACKUP_DIR"/*; do
    bucket=$(basename "$dir")
    echo "- Création du bucket: $bucket"
    mc mb --ignore-existing "$ALIAS_NAME/$bucket"
    echo "  ↪️ Restauration des fichiers..."
    mc mirror --overwrite "$dir" "$ALIAS_NAME/$bucket"
done

echo "✅ Restauration terminée depuis : $archive"

# === 8. NETTOYAGE TEMPORAIRE ===
rm -rf "$TMP_RESTORE_DIR"
echo "🧹 Nettoyage terminé."
