#!/bin/bash

# Vérifie si on est root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "❌ Ce script doit être exécuté en tant que root !"
    echo -e "👉 Utilise 'sudo $0' ou connecte-toi avec un compte privilégié."
    exit 1
fi

echo "🔍 Détection des points de montage XFS et EXT utiles"
echo "---------------------------------------------------"

# Types de FS qu'on veut tester
SUPPORTED_FS="xfs|ext3|ext4"

# Montages à ignorer
EXCLUDED_MOUNTS="boot|snap|tmpfs|devtmpfs|squashfs|fuse|ramfs|autofs|proc|sysfs|debugfs|configfs|securityfs|selinuxfs|bpf|mqueue|hugetlbfs|tracefs|cgroup|selinux"

# Tableaux pour les résultats
declare -A acl_status

# Traitement des lignes de mount
while read -r line; do
    # Extraire le périphérique, point de montage et type de FS
    dev=$(echo "$line" | awk '{print $1}')
    mnt=$(echo "$line" | awk '{print $3}')
    fstype=$(echo "$line" | awk '{print $5}')

    # On ne garde que les types supportés
    echo "$fstype" | grep -Eq "$SUPPORTED_FS" || continue

    # On ignore les points de montage non pertinents
    echo "$mnt" | grep -Eq "$EXCLUDED_MOUNTS" && continue

    # Test ACL
    testfile="$mnt/.acl_test_$$"
    echo -n "👉 Test sur $mnt [$fstype] : "
    if touch "$testfile" 2>/dev/null && setfacl -m u:$(whoami):rw "$testfile" 2>/dev/null; then
        echo "✅ ACL fonctionnel"
        acl_status["$mnt"]="SUPPORTED"
        rm -f "$testfile"
    else
        echo "❌ ACL non fonctionnel ou permission refusée"
        acl_status["$mnt"]="NOT SUPPORTED"
    fi

done < <(mount)

# Résumé final
echo -e "\n📊 Résumé final :"
printf "%-30s | %-10s\n" "Point de montage" "ACL Status"
printf "%-30s-+-%-10s\n" "$(printf '%.0s-' {1..30})" "$(printf '%.0s-' {1..10})"

for mnt in "${!acl_status[@]}"; do
    printf "%-30s | %-10s\n" "$mnt" "${acl_status[$mnt]}"
done
