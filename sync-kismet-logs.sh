#!/bin/bash

#####################################
# Configuration                     #
#####################################
S3_BUCKET="s3://sworthlabstestbucket01"
LOCAL_LOG_DIR="/home/driver/kismet_logs"
TMP_DIR="/tmp/kismet_verify"
AWS_CLI="/usr/bin/aws"
HASH_CMD="/usr/bin/sha256sum"
FILE_EXTENSIONS=("kismet" "pcap" "pcapng")
NETWORK_CHECK_HOST="8.8.8.8"
KISMET_SERVICE="kismet"

#####################################
# Prevent Concurrent Syncs          #
#####################################
if [ -f "$LOCKFILE" ]; then
    echo "[!] Sync already in progress. Exiting."
    exit 1
fi


#####################################
# Functions                         #
#####################################
function log() {
    echo "[$(date '+%F %T')] $1"
}

#####################################
# Check for Internet Connectivity   #
#####################################
ping -c 1 -W 2 "$NETWORK_CHECK_HOST" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    log "[!] No internet connectivity. Exiting sync daemon."
    exit 0
fi

log "[*] Internet connectivity detected."

#Lock Kismet from starting
LOCKFILE="/tmp/kismet-sync.lock"
touch "$LOCKFILE"


#####################################
# Stop Kismet Service               #
#####################################
log "[*] Stopping Kismet service..."
systemctl stop "$KISMET_SERVICE"
sleep 10

#####################################
# Sync Files to S3                  #
#####################################
mkdir -p "$TMP_DIR"

for ext in "${FILE_EXTENSIONS[@]}"; do
    for file in "$LOCAL_LOG_DIR"/*."$ext"; do
        [ -e "$file" ] || continue

        filename=$(basename "$file")
        hashfile="$file.sha256"

        log "[*] Processing: $filename"

        $HASH_CMD "$file" | awk '{print $1}' > "$hashfile"
        if [ $? -ne 0 ]; then
            log "[!] Failed to generate hash for $filename"
            continue
        fi

        $AWS_CLI s3 cp "$file" "$S3_BUCKET/$filename"
        $AWS_CLI s3 cp "$hashfile" "$S3_BUCKET/$filename.sha256"

        if [ $? -ne 0 ]; then
            log "[!] Upload failed for $filename"
            continue
        fi

        $AWS_CLI s3 cp "$S3_BUCKET/$filename" "$TMP_DIR/$filename"
        if [ $? -ne 0 ]; then
            log "[!] Download for verification failed for $filename"
            continue
        fi

        remote_hash=$($HASH_CMD "$TMP_DIR/$filename" | awk '{print $1}')
        original_hash=$(cat "$hashfile")

        if [[ "$remote_hash" == "$original_hash" ]]; then
            log "[+] Verified: $filename. Deleting local copy."
            rm -f "$file" "$hashfile"
        else
            log "[!] Hash mismatch for $filename — keeping local copy."
        fi

        rm -f "$TMP_DIR/$filename"
    done
done

#remove the Kismet Lockout
rm -f "$LOCKFILE"

log "[✓] Sync complete. Exiting."
exit 0
