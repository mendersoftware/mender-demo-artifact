#!/bin/sh
set -e

PROC=$(cat /proc/cpuinfo | grep "model name" | sed -n -e 's/^model name.*: //p' | head -n1)
DEVICE_TYPE=$(sed -e 's/^device_type=//' /var/lib/mender/device_type 2>/dev/null || uname -m)
MENDER_VERSION=$(mender -version 2>/dev/null | head -n1)
MENDER_VERSION=${MENDER_VERSION:-N/A}
INVENTORY="$(for script in /usr/share/mender/inventory/mender-inventory-*; do $script || true; done)"
cat >/data/www/localhost/htdocs/device-info.js <<EOF
  mender_server = {
    "Web server": "$(hostname)",
    "Server address(es)": "[ $(echo "$INVENTORY" | sed -ne '/^ipv4/{s/^[^=]*=//; s,/.*$,,; p}' | tr '\n' ' ')]"
  }
  mender_identity = {
    "Device ID": "",
    "mac": "$(cat /sys/class/net/eth0/address)"
  }
  mender_inventory = {
    "device_type": "$DEVICE_TYPE",
    "mender_client_version": "$MENDER_VERSION",
    "os": "$(cat /proc/version)",
    "cpu": "$PROC",
    "kernel": "$(uname -r)"
  }
EOF
cd /data/www/localhost/htdocs
../busybox httpd -f -p 85 &
BUSYBOX_PID=$!
# Trick to catch failures: Wait a few seconds for busybox to exit. If it does,
# there's likely an error, and the kill will fail, which `set -e` will handle.
sleep 3
kill -0 $BUSYBOX_PID
if which systemd-notify 2>/dev/null; then
 systemd-notify --ready || true
fi
echo "$BUSYBOX_PID" > /var/run/mender-demo-artifact
wait $BUSYBOX_PID
