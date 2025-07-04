#!/bin/bash

# check-network-status.sh
# This script checks for internet connectivity.
# If not available, it will restart the Kismet service.

#####################################
# Configuration                     #
#####################################
PING_TARGET="8.8.8.8"
KISMET_SERVICE="kismet"
LOCKFILE="/tmp/kismet-sync.lock"

#####################################
# Check for Internet Connectivity   #
#####################################
if ping -q -c1 $PING_TARGET >/dev/null 2>&1; then
    echo "[*] Internet detected. Kismet will not restart."
    exit 0
fi

# Skip if a sync is in progress
if [ -f "$LOCKFILE" ]; then
    echo "[!] Sync is in progress. Skipping Kismet restart."
    exit 0
fi

echo "[!] Internet is down. Restarting Kismet..."
systemctl restart "$KISMET_SERVICE"
