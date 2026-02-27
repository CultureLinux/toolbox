#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 -d domain -p php_version -n projet [-u deploy_user]"
    echo
    echo "  -d domain        => Nom du domaine (ex: vm3.dg.lan)"
    echo "  -p php_version   => Version PHP Remi (ex: 83 pour php83-php-fpm)"
    echo "  -n projet        => Nom du projet (/home/web/www/nomduprojet et DB avec même nom)"
    echo "  -u deploy_user   => User système pour le projet (optionnel, défaut: web)"
    exit 1
}

while getopts "d:p:n:u:" opt; do
    case "$opt" in
        d) DOMAIN=${OPTARG} ;;
        p) PHP_VERSION=${OPTARG} ;;
        n) PROJET=${OPTARG} ;;
        u) DEPLOY_USER=${OPTARG} ;;
        *) usage ;;
    esac
done

if [[ -z "${DOMAIN:-}" || -z "${PHP_VERSION:-}" || -z "${PROJET:-}" ]]; then
    echo "❌ Paramètre manquant"
    usage
fi

DEPLOY_USER=${DEPLOY_USER:-web}
USER="$DEPLOY_USER"

# --- Création du user si inexistant ---
if ! id "$USER" &>/dev/null; then
    echo "⚡ Création de l'utilisateur système '$USER'"
    sudo useradd -m -s /bin/bash "$USER"
fi

# --- Ajout de nginx dans le groupe du user ---
sudo usermod -aG "$USER" nginx

# --- Vérification du répertoire /home/$USER/www ---
BASE_PATH="/home/$USER/www"

if [[ ! -d "$BASE_PATH" ]]; then
    echo "⚡ Création du répertoire '$BASE_PATH'"
    sudo mkdir -p "$BASE_PATH"
    sudo chown "$USER:$USER" "$BASE_PATH"
fi

PROJECT_ROOT="$BASE_PATH/$PROJET"
NGINX_AVAILABLE="/etc/nginx/sites-available/${DOMAIN}.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}.conf"
PHPFPM_CONF="/etc/opt/remi/php${PHP_VERSION}/php-fpm.d/${DOMAIN}.conf"
SOCKET="/var/run/php${PHP_VERSION}-fpm.${DOMAIN}.socket"

# --- Garde-fou existants ---
if [[ -f "$NGINX_AVAILABLE" ]]; then
    echo "❌ Vhost déjà existant dans sites-available."
    exit 1
fi

if [[ -L "$NGINX_ENABLED" ]]; then
    echo "❌ Symlink déjà existant dans sites-enabled."
    exit 1
fi

if [[ -f "$PHPFPM_CONF" ]]; then
    echo "❌ Pool PHP-FPM pour '$DOMAIN' déjà existant ($PHPFPM_CONF). Abandon."
    exit 1
fi

# --- Confirmation avant de continuer ---
echo "⚠️  Tu es sur le point de créer :"
echo "    Domaine        : $DOMAIN"
echo "    PHP Version    : $PHP_VERSION"
echo "    Projet Path    : $PROJECT_ROOT"
echo "    User système   : $USER"
echo "    Base de données: $PROJET (user/password = $PROJET)"
echo
read -p "Veux-tu continuer ? (yes/no) " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "❌ Abandon par l'utilisateur."
    exit 1
fi

# --- Nginx vhost ---
sudo tee "$NGINX_AVAILABLE" > /dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log /var/log/nginx/${DOMAIN}.error.log warn;

    ssl_certificate "/etc/nginx/ssl/_.local.clinux.fr.crt";
    ssl_certificate_key "/etc/nginx/ssl/_.local.clinux.fr.key;
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout 10m;
    ssl_ciphers PROFILE=SYSTEM;
    ssl_prefer_server_ciphers on;

    root $PROJECT_ROOT/public;

    location / {
        try_files \$uri /index.php\$is_args\$args;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:$SOCKET;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 300;
    }

    location ~ /\.(env|git|ht|svn|composer|docker) {
        deny all;
    }
}
EOF

sudo ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"

echo "✔ Vhost créé et activé"

# --- PHP-FPM pool ---
sudo tee "$PHPFPM_CONF" > /dev/null <<EOF
[$DOMAIN]

listen = $SOCKET
listen.owner = nginx
listen.group = nginx
listen.mode = 0660

user = $USER
group = $USER

pm = ondemand
pm.max_children = 2
pm.start_servers = 1
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
pm.process_idle_timeout = 60s

php_admin_value[open_basedir] = $PROJECT_ROOT:/tmp

chdir = $PROJECT_ROOT
EOF

echo "✔ PHP-FPM pool créé : $PHPFPM_CONF"

# --- Reload services ---
sudo nginx -t
sudo systemctl reload php${PHP_VERSION}-php-fpm
sudo systemctl reload nginx

echo "✔ Services rechargés : Nginx + PHP${PHP_VERSION}-FPM"

# --- Création base de données + user (optionnel) ---
echo
read -p "Veux-tu créer la base de données MySQL pour '$PROJET' ? (yes/no) " CREATE_DB

if [[ "$CREATE_DB" == "yes" ]]; then
    echo "⚡ Création de la base de données et user MySQL : $PROJET"

    mysql -e "CREATE DATABASE IF NOT EXISTS \`$PROJET\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '$PROJET'@'%' IDENTIFIED BY '$PROJET';"
    mysql -e "CREATE USER IF NOT EXISTS '$PROJET'@'localhost' IDENTIFIED BY '$PROJET';"
    mysql -e "GRANT ALL PRIVILEGES ON \`$PROJET\`.* TO '$PROJET'@'%';"
    mysql -e "GRANT ALL PRIVILEGES ON \`$PROJET\`.* TO '$PROJET'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    echo "✔ Base de données $PROJET créée avec user/password = $PROJET"
else
    echo "ℹ️  Création de la base ignorée."
fi