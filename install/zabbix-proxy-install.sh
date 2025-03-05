#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: JDDNet
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.zabbix.com/

# Import Functions und Setup
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies with the 3 core dependencies (curl;sudo;mc)
msg_info "Installing Dependencies"
$STD apt-get install -y curl sudo mc 
msg_ok "Installed Dependencies"

msg_info "Installing Zabbix Proxy"
cd /tmp
wget -q https://repo.zabbix.com/zabbix/7.2/release/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.2+debian12_all.deb
$STD dpkg -i /tmp/zabbix-release_latest_7.2+debian12_all.deb
$STD apt-get update
$STD apt-get install -y zabbix-proxy-pgsql zabbix-sql-scripts
$STD apt-get install -y zabbix-agent2 zabbix-agent2-plugin-postgresql
sed -i "s|^Hostname=.*|# Hostname=|" /etc/zabbix/zabbix_proxy.conf
sed -i "s|^# HostnameItem=.*|HostnameItem=system.hostname|" /etc/zabbix/zabbix_proxy.conf
msg_ok "Installed Zabbix Proxy"

msg_info "Setting up PostgreSQL"
$STD apt-get install -y postgresql
DB_NAME=zabbix_proxydb
DB_USER=zabbix
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
cat /usr/share/zabbix/sql-scripts/postgresql/proxy.sql | sudo -u $DB_USER psql $DB_NAME &>/dev/null
sed -i "s/^DBName=.*/DBName=$DB_NAME/" /etc/zabbix/zabbix_proxy.conf
sed -i "s/^DBUser=.*/DBUser=$DB_USER/" /etc/zabbix/zabbix_proxy.conf
sed -i "s/^# DBPassword=.*/DBPassword=$DB_PASS/" /etc/zabbix/zabbix_proxy.conf
echo "" >~/zabbix.creds
echo "zabbix Database Credentials" >>~/zabbix.creds
echo "" >>~/zabbix.creds
echo -e "zabbix Database User: \e[32m$DB_USER\e[0m" >>~/zabbix.creds
echo -e "zabbix Database Password: \e[32m$DB_PASS\e[0m" >>~/zabbix.creds
echo -e "zabbix Database Name: \e[32m$DB_NAME\e[0m" >>~/zabbix.creds
msg_ok "Set up PostgreSQL"

msg_info "Setting up TLS PSK"
TLS_ID=$(hostname)
TLS_PSK=$(openssl rand -hex 32)
echo $TLS_PSK >>/etc/zabbix/tls.psk
sed -i "s|^# TLSConnect=.*|TLSConnect=psk|" /etc/zabbix/zabbix_proxy.conf
sed -i "s|^# TLSPSKIdentity=.*|TLSPSKIdentity=$TLS_ID|" /etc/zabbix/zabbix_proxy.conf
sed -i "s|^# TLSPSKFile=.*|TLSPSKFile=/etc/zabbix/tls.psk|" /etc/zabbix/zabbix_proxy.conf
echo -e "zabbix TLS PSK Identity: \e[32m$TLS_ID\e[0m" >>~/zabbix.creds
echo -e "zabbix TLS PSK: \e[32m$TLS_PSK\e[0m" >>~/zabbix.creds
msg_ok "Set up TLS PSK"

msg_info "Setting up SNMP Trapper"
$STD apt-get install -y libnet-snmp-perl snmp snmptrapd libsnmp-perl snmpd
$STD curl -o /usr/bin/zabbix_trap_receiver.pl https://git.zabbix.com/projects/ZBX/repos/zabbix/raw/misc/snmptrap/zabbix_trap_receiver.pl
$STD chmod +x /usr/bin/zabbix_trap_receiver.pl
$STD mkdir /var/log/snmptrap
sed -i "s|^\$SNMPTrapperFile.*|\$SNMPTrapperFile = '/var/log/snmptrap/snmptrap.log';|" /usr/bin/zabbix_trap_receiver.pl
echo "authCommunity execute public" >> /etc/snmp/snmptrapd.conf
echo "perl do "/usr/bin/zabbix_trap_receiver.pl";" >> /etc/snmp/snmptrapd.conf
cat > /etc/logrotate.d/snmptrap <<EOL
/var/log/snmptrap/snmptrap.log {
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
}
EOL
msg_ok "Set up SNMP Trapper"

msg_info "Setting up Zabbix Proxy with SNMP Trapper"
sed -i "s|^SNMPTrapperFile=.*|SNMPTrapperFile=/var/log/snmptrap/snmptrap.log|" /etc/zabbix/zabbix_proxy.conf
sed -i "s|^# StartSNMPTrapper=.*|StartSNMPTrapper=1|" /etc/zabbix/zabbix_proxy.conf
msg_ok "Set up Zabbix Proxy with SNMP Trapper"

msg_info "Starting Services"
systemctl restart zabbix-agent2 zabbix-proxy snmptrapd
systemctl enable -q --now zabbix-agent2 zabbix-proxy snmptrapd
msg_ok "Started Services"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /tmp/zabbix-release_latest_7.2+debian12_all.deb
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"