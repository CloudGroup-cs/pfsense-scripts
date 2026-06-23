#!/bin/sh
/usr/local/bin/beep -p 500 25 && /usr/local/bin/beep -p 750 25 && /usr/local/bin/beep -p 1000 25
# Variables
LOG="/root/pfsense_upgrade_$(date +%F_%H-%M).log"
echo "==== pfSense automated upgrade started $(date) ====" | tee -a $LOG
# 01. Detect ZFS
echo "[1/9] Detect ZFS file system" | tee -a $LOG
if ! zfs list >/dev/null 2>&1; then
  echo "ERROR: No ZFS detected, rollback not possible!" | tee -a $LOG
  exit 1
fi

# 02. Backup configuration
echo "[2/9] Backing up config.xml" | tee -a $LOG
cp /cf/conf/config.xml /root/config.xml.bak.upgrade

# 03. Create boot environment
echo "[3/9] Creating boot environment" | tee -a $LOG
# First create be snapshot
if bectl list | grep -q "^preupgrade "; then
    bectl destroy preupgrade
fi
bectl create -r "preupgrade" >> $LOG 2>&1

if [ $? -ne 0 ]; then
  echo "ERROR: Failed to create boot environment" | tee -a $LOG
  exit 1
fi

# 04. Prepare pfSense config and repos
echo "[4/9] Preparing pfSense config and repos for upgrade" | tee -a $LOG
mkdir -p /usr/local/etc/pfSense/pkg/repos
# 04.a pfSense.conf
cat << 'EOF' > /usr/local/etc/pkg/repos/pfSense.conf
FreeBSD: { enabled: no }

pfSense-core: {
    url: "pkg+https://pkg.pfsense.org/pfSense_v2_7_2_amd64-core",
    mirror_type: "srv",
    signature_type: "fingerprints",
    fingerprints: "/usr/local/share/pfSense/keys/pkg",
    enabled: yes
}

pfSense: {
    url: "pkg+https://pkg.pfsense.org/pfSense_v2_7_2_amd64-pfSense_v2_7_2",
    mirror_type: "srv",
    signature_type: "fingerprints",
    fingerprints: "/usr/local/share/pfSense/keys/pkg",
    enabled: yes
}
EOF
# 04.b pfSense-repo-2.7.2.abi
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.7.2.abi
FreeBSD:14:amd64
EOF
# 04.c pfSense-repo-2.7.2.altabi
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.7.2.altabi
freebsd:14:x86:64
EOF
# 04.d pfSense-repo-2.7.2.conf
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.7.2.conf
FreeBSD: { enabled: no }

pfSense-core: {
    url: "pkg+https://pkg.pfsense.org/pfSense_v2_7_2_amd64-core",
    mirror_type: "srv",
    signature_type: "fingerprints",
    fingerprints: "/usr/local/share/pfSense/keys/pkg",
    enabled: yes
}

pfSense: {
    url: "pkg+https://pkg.pfsense.org/pfSense_v2_7_2_amd64-pfSense_v2_7_2",
    mirror_type: "srv",
    signature_type: "fingerprints",
    fingerprints: "/usr/local/share/pfSense/keys/pkg",
    enabled: yes
}
EOF
# 04.e pfSense-repo-2.7.2.default
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.7.2.default
1
EOF
# 04.f pfSense-repo-2.7.2.descr
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.7.2.descr
Previous Stable Version (2.7.2)
EOF
# 04.g pfSense-repo-2.7.2.name
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.7.2.name
2.7.2
EOF
# 04.h pfSense-repo-2.8.1.abi
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.8.1.abi
FreeBSD:15:amd64
EOF
# 04.i pfSense-repo-2.8.1.altabi
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.8.1.altabi
freebsd:15:x86:64
EOF
# 04.j pfSense-repo-2.8.1.conf
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.8.1.conf
FreeBSD: { enabled: no }

pfSense-core: {
    url: "pkg+https://pkg.pfsense.org/pfSense_v2_8_1_amd64-core",
    mirror_type: "srv",
    signature_type: "fingerprints",
    fingerprints: "/usr/local/share/pfSense/keys/pkg",
    enabled: yes
}

pfSense: {
    url: "pkg+https://pkg.pfsense.org/pfSense_v2_8_1_amd64-pfSense_v2_8_1",
    mirror_type: "srv",
    signature_type: "fingerprints",
    fingerprints: "/usr/local/share/pfSense/keys/pkg",
    enabled: yes
}
EOF
# 04.k pfSense-repo-2.8.1.descr
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.8.1.descr
Current Stable Version (2.8.1)
EOF
# 04.l pfSense-repo-2.8.1.name
cat << 'EOF' > /usr/local/etc/pfSense/pkg/repos/pfSense-repo-2.8.1.name
2_8_1
EOF

# 05. Ensure correct upgrade branch & set to config
echo "[5/9] Switching to latest branch" | tee -a $LOG
sed -i '' 's#<pkg_repo_conf_path>.*</pkg_repo_conf_path>#<pkg_repo_conf_path>/usr/local/etc/pfSense/pkg/repos/pfSense-repo-2_8_1.conf</pkg_repo_conf_path>#' /conf/config.xml
grep -q "<gitsync>" /conf/config.xml || sed -i '' '/<earlyshellcmd>/a\
\<gitsync>\
\<repositoryurl></repositoryurl>\
\<branch></branch>\
\</gitsync>
' /conf/config.xml
/etc/rc.reload_all
sleep 60

# 06. Track packages
echo "[6/9] Tracking packages" | tee -a $LOG
# pkg update -f >> $LOG 2>&1
# pkg upgrade -y >> $LOG 2>&1
pkg info > /root/pkg-before.txt
sleep 10
# 07. Perform upgrade
echo "[7/9] Running pfSense upgrade" | tee -a $LOG
# pfSense-upgrade -c
certctl rehash
sleep 10
env ASSUME_ALWAYS_YES=yes pfSense-upgrade -y -R >> $LOG 2>&1
if [ $? -ne 0 ]; then
  echo "ERROR: Upgrade failed BEFORE reboot" | tee -a $LOG
  exit 1
fi
sleep 10
# 08. Install post-boot validator
echo "[8/9] Installing post-upgrade validation script" | tee -a $LOG
cat << 'EOF' > /root/post_upgrade_check.sh
#!/bin/sh
LOG_POST="/root/post_upgrade_check.log"
echo "==== Post-upgrade validation $(date) ====" >> $LOG_POST
sleep 120
# Core system checks
FAIL=0
echo "Checking system..."
if ! uname -a >/dev/null 2>&1; then
  echo "System check failed" >> $LOG_POST
  FAIL=1
else
  echo "System check OK" >> $LOG_POST
fi
echo "Checking PHP..."
if ! php -v >/dev/null 2>&1; then
  echo "PHP failed" >> $LOG_POST
  FAIL=1
else
  echo "PHP OK" >> $LOG_POST
fi
echo "Checking config.xml..."
if ! [ -f /conf/config.xml ] >/dev/null 2>&1; then
  echo "config.xml missing" >> $LOG_POST
  FAIL=1
else
  echo "config.xml present" >> $LOG_POST
fi
echo "Validating config.xml..."
echo "Checking system..."
if ! php -r 'simplexml_load_file("/conf/config.xml") or exit(1);' >/dev/null 2>&1; then
  echo "config.xml invalid" >> $LOG_POST
  FAIL=1
else
  echo "config.xml valid" >> $LOG_POST
fi
echo "Checking firewall..."
if ! pfctl -s info | grep -q "Status: Enabled" >/dev/null 2>&1; then
  echo "Firewall not enabled" >> $LOG_POST
  FAIL=1
else
  echo "Firewall enabled" >> $LOG_POST
fi
echo "Checking default route..."
if route -n get default >/dev/null 2>&1; then
  echo "Default route OK" >> $LOG_POST  
else
  echo "No default route" >> $LOG_POST
  FAIL=1
fi
echo "Checking internet connectivity..."
if ! nc -z 8.8.8.8 53 >/dev/null 2>&1; then
  echo "Cannot reach internet" >> $LOG_POST
  FAIL=1
else
  echo "Internet reachable" >> $LOG_POST
fi
# Package integrity check (NOW in correct place)
echo "Running pkg integrity check..." >> $LOG_POST
pkg check -da >> $LOG_POST 2>&1
if [ $? -ne 0 ]; then
  echo "Package integrity check FAILED" >> $LOG_POST
  FAIL=1
else
  echo "Package integrity check OK" >> $LOG_POST
fi
# Optional: force reinstall missing/broken packages
# pkg install -fy >> $LOG_POST 2>&1
# Tracking packages after upgrade
pkg info > /root/pkg-after.txt
if [ $FAIL -ne 0 ]; then
  echo "VALIDATION FAILED - rolling back" >> $LOG_POST
  bectl activate "preupgrade"
  reboot
else
  echo "Validation successful" >> $LOG_POST
  PFSENSE_VERSION=$(cat /etc/version)
  if [ "$PFSENSE_VERSION" = "2.7.2-RELEASE" ]; then
    certctl rehash
    env ASSUME_ALWAYS_YES=yes pfSense-upgrade -y >> $LOG_POST
  else
    pkg update
    pkg install -y pfSense-pkg-zabbix-agent6 >> $LOG_POST
    # Cleanup: run once
    rm -f /root/post_upgrade_check.sh
  fi
fi
EOF

chmod +x /root/post_upgrade_check.sh
# Add to rc.local
echo "/root/post_upgrade_check.sh" >> /etc/rc.local
# 09. Reboot
echo "[9/9] Rebooting system" | tee -a $LOG
shutdown -r +1 "pfSense upgrade completed"
echo "==== Upgrade finished $(date) ====" | tee -a $LOG
/usr/local/bin/beep -p 1000 25 && /usr/local/bin/beep -p 750 25 && /usr/local/bin/beep -p 500 25
