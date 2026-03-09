#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Drop-OSS/drop

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  nginx
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql
PG_DB_NAME="drop" PG_DB_USER="drop" setup_postgresql_db
NODE_VERSION="22" setup_nodejs
setup_rust

fetch_and_deploy_gh_release "drop" "Drop-OSS/drop" "tarball"

msg_info "Initializing Submodules"
cd /opt/drop
$STD git submodule update --init --recursive
msg_ok "Initialized Submodules"

msg_info "Installing pnpm and Dependencies"
$STD corepack enable
$STD corepack prepare pnpm@latest --activate
$STD pnpm install
msg_ok "Installed pnpm and Dependencies"

msg_info "Building Application"
cd /opt/drop
$STD pnpm run build
msg_ok "Built Application"

msg_info "Building Torrential"
cd /opt/drop/torrential
source /root/.profile
export PATH="/root/.cargo/bin:$PATH"
$STD cargo build --release
msg_ok "Built Torrential"

msg_info "Setting up Directories"
mkdir -p /opt/drop/data/library
msg_ok "Set up Directories"

msg_info "Configuring Environment"
cat <<EOF >/opt/drop/.env
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
EXTERNAL_URL=http://${LOCAL_IP}:3000
NGINX_CONFIG=/opt/drop/nginx.conf
DATA=/opt/drop/data
EOF
msg_ok "Configured Environment"

msg_info "Running Database Migrations"
cd /opt/drop
set -a && source /opt/drop/.env && set +a
$STD npm install prisma@7.3.0 dotenv
$STD npx prisma migrate deploy
msg_ok "Ran Database Migrations"

msg_info "Configuring NGINX"
cp /opt/drop/build/nginx.conf /opt/drop/nginx.conf
sed -i "s|proxy_pass http://localhost:3000;|proxy_pass http://127.0.0.1:3000;|" /opt/drop/nginx.conf
cat <<EOF >/etc/nginx/sites-available/drop.conf
upstream drop_backend {
    server 127.0.0.1:3000;
}

server {
    listen 80;
    server_name _;

    client_max_body_size 1G;

    location / {
        proxy_pass http://drop_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_redirect off;
        proxy_buffering off;
        proxy_read_timeout 86400;
    }
}
EOF
ln -sf /etc/nginx/sites-available/drop.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl enable -q --now nginx
msg_ok "Configured NGINX"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/drop.service
[Unit]
Description=Drop Game Distribution Platform
After=network.target postgresql.service nginx.service
Requires=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/drop
EnvironmentFile=/opt/drop/.env
Environment=PATH=/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/bin/node ./.output/server/index.mjs
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now drop
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc