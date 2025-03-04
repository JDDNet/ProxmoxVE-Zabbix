#!/usr/bin/env bash
#source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
source <(curl -s https://raw.githubusercontent.com/JDDNet/ProxmoxVE-Zabbix/refs/heads/Zabbix-Proxy/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: JDDNet
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.zabbix.com/

APP="Zabbix-Proxy"
var_tags="monitoring"
var_cpu="2"
var_ram="8192"
var_disk="16"
var_os="ubuntu"
var_version="24.04"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -f /etc/zabbix/zabbix_proxy.conf ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Stopping ${APP} Services"
    systemctl stop zabbix-agent2 zabbix-proxy snmptrapd
    msg_ok "Stopped ${APP} Services"

    msg_info "Backing up $APP LXC"
    mkdir -p /opt/zabbix-proxy-backup/
    cp /etc/zabbix/zabbix_proxy.conf /opt/zabbix-proxy-backup/
    cp /etc/snmp/snmptrapd.conf /opt/zabbix-proxy-backup/
    cp /usr/bin/zabbix_trap_receiver.pl /opt/zabbix-proxy-backup/
    cp -R /usr/share/zabbix/ /opt/zabbix-proxy-backup/
    cp -R /usr/share/zabbix-* /opt/zabbix-proxy-backup/
    rm -Rf /etc/apt/sources.list.d/zabbix.list
    if [ -f ~/zabbix.creds ]; then
    source ~/zabbix.creds
    DB_USER=$(grep 'zabbix Database User' ~/zabbix.creds | awk '{print $4}')
    DB_PASS=$(grep 'zabbix Database Password' ~/zabbix.creds | awk '{print $4}')
    DB_NAME=$(grep 'zabbix Database Name' ~/zabbix.creds | awk '{print $4}')
    $STD sudo -u postgres pg_dump -U $DB_USER -d $DB_NAME -W $DB_PASS -F tar -f /opt/zabbix-proxy-backup/zabbix-proxy-backup.sql.tar
    fi
    msg_info "Backup of $APP LXC Complete"

    msg_info "Updating $APP LXC"
    cd /tmp
    wget -q https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.2+ubuntu24.04_all.deb
    $STD dpkg -i zabbix-release_latest_7.2+ubuntu24.04_all.deb
    $STD apt-get update
    $STD apt-get install --only-upgrade zabbix-proxy-pgsql zabbix-sql-scripts zabbix-agent2 zabbix-agent2-plugin-postgresql postgresql net-snmp-utils net-snmp-perl net-snmp

    msg_info "Starting ${APP} Services"
    systemctl start zabbix-agent2 zabbix-proxy snmptrapd
    msg_ok "Started ${APP} Services"

    msg_info "Cleaning Up"
    rm -rf /tmp/zabbix-release_latest_7.2+ubuntu24.04_all.deb
    msg_ok "Cleaned"
    msg_ok "Updated Successfully"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/zabbix${CL}"
