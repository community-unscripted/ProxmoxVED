#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Drop-OSS/drop

APP="Drop"
var_tags="${var_tags:-games;media;distribution}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/drop ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "drop" "Drop-OSS/drop"; then
    msg_info "Stopping Services"
    systemctl stop drop
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp -r /opt/drop/data /opt/drop_data_backup
    cp /opt/drop/.env /opt/drop_env_backup
    cp -r /opt/drop/prisma /opt/drop_prisma_backup
    msg_ok "Backed up Data"

    msg_info "Cloning Drop Repository"
    rm -rf /opt/drop
    $STD git clone --recursive --depth 1 https://github.com/Drop-OSS/drop.git /opt/drop
    msg_ok "Cloned Drop Repository"

    msg_info "Installing Dependencies"
    $STD corepack enable
    $STD corepack prepare pnpm@latest --activate
    $STD pnpm install
    msg_ok "Installed Dependencies"

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

    msg_info "Restoring Data"
    cp -r /opt/drop_data_backup/. /opt/drop/data
    cp /opt/drop_env_backup /opt/drop/.env
    cp -r /opt/drop_prisma_backup/. /opt/drop/prisma
    rm -rf /opt/drop_data_backup /opt/drop_env_backup /opt/drop_prisma_backup
    msg_ok "Restored Data"

    msg_info "Running Database Migrations"
    cd /opt/drop
    set -a && source /opt/drop/.env && set +a
    $STD npx prisma migrate deploy
    msg_ok "Ran Database Migrations"

    msg_info "Starting Services"
    systemctl start drop
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"