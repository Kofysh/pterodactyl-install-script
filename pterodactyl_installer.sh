#!/bin/bash

# Demande du mot de passe et du nom de domaine
read -p "Entrez le mot de passe pour l'utilisateur 'pterodactyl' de la base de données : " db_password
read -p "Entrez votre nom de domaine (ex: example.com) : " domain_name

# Mise à jour du système et installation des dépendances
echo "Mise à jour du système et installation des dépendances..."
apt update && apt upgrade -y
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg

# Ajouter le dépôt Node.js
curl -sL https://deb.nodesource.com/setup_16.x | bash -
apt install -y nodejs

# Installer MariaDB
echo "Installation de MariaDB..."
apt install -y mariadb-server mariadb-client
systemctl start mariadb
systemctl enable mariadb

# Sécuriser MariaDB
echo "Sécurisation de MariaDB..."
mysql_secure_installation

# Créer la base de données pour Pterodactyl
echo "Création de la base de données pour Pterodactyl..."
mysql -u root -p -e "CREATE DATABASE pterodactyl;"
mysql -u root -p -e "CREATE USER 'pterodactyl'@'localhost' IDENTIFIED BY '$db_password';"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON pterodactyl.* TO 'pterodactyl'@'localhost';"
mysql -u root -p -e "FLUSH PRIVILEGES;"

# Installation de PHP et des extensions requises
echo "Installation de PHP et des extensions requises..."
add-apt-repository ppa:ondrej/php
apt update
apt install -y php8.0 php8.0-fpm php8.0-cli php8.0-mysql php8.0-gd php8.0-mbstring php8.0-curl php8.0-xml php8.0-bcmath php8.0-zip unzip

# Télécharger Pterodactyl Panel
echo "Téléchargement de Pterodactyl Panel..."
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# Installer Composer
echo "Installation de Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# Installer les dépendances de Pterodactyl Panel
echo "Installation des dépendances de Pterodactyl Panel..."
composer install --no-dev --optimize-autoloader

# Configuration de l'environnement
echo "Configuration de l'environnement..."
cp .env.example .env
php artisan key:generate

# Configuration de la base de données dans .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$db_password/" .env

# Installer Pterodactyl Panel
echo "Installation de Pterodactyl Panel..."
php artisan p:environment:setup
php artisan p:environment:database
php artisan migrate --seed --force

# Configuration de Nginx
echo "Configuration de Nginx..."
apt install -y nginx
cat > /etc/nginx/sites-available/pterodactyl <<EOL
server {
    listen 80;
    server_name $domain_name;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.access.log;
    error_log /var/log/nginx/pterodactyl.error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.0-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

ln -s /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/pterodactyl
nginx -t
systemctl restart nginx

# Installation de Pterodactyl Wings
echo "Installation de Pterodactyl Wings..."
curl -Lo wings.tar.gz https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64.tar.gz
tar -xzvf wings.tar.gz -C /usr/local/bin
chmod +x /usr/local/bin/wings

# Configuration de Wings
echo "Configuration de Wings..."
mkdir -p /etc/pterodactyl
cat > /etc/systemd/system/wings.service <<EOL
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=600

[Install]
WantedBy=multi-user.target
EOL

systemctl enable wings
systemctl start wings

echo "Installation terminée ! Veuillez finaliser la configuration de Pterodactyl via le panneau d'administration."
