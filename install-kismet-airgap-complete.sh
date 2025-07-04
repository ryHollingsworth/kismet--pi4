#!/bin/bash

set -e

########################################
# Interactive Setup for Kismet Airgap #
########################################

echo "[*] Starting Kismet Airgap Installer..."

# Prompt for input
read -p "Enter username for Pi (default: driver): " WARDRIVE_USER
WARDRIVE_USER=${WARDRIVE_USER:-driver}

read -p "Do you want to configure wlan0 as an access point? (y/n): " SETUP_AP
if [[ "$SETUP_AP" =~ ^[Yy]$ ]]; then
    read -p "Enter desired SSID: " AP_SSID
    read -s -p "Enter desired AP password (8+ characters): " AP_PASS
    echo
fi

read -p "Enter your AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -s -p "Enter your AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo
read -p "Enter your S3 Bucket name: " S3_BUCKET

GPS_DEVICE="/dev/ttyACM0"
WIFI_INTERFACE="wlan1"
KISMET_LOG_DIR="/home/$WARDRIVE_USER/kismet_logs"

echo "[*] Updating and installing packages..."
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git gpsd gpsd-clients python3-gps kismet dkms build-essential libelf-dev linux-headers-$(uname -r) awscli netfilter-persistent iptables-persistent

echo "[*] Installing Alfa AWUS1900 drivers..."
git clone https://github.com/aircrack-ng/rtl8812au.git
cd rtl8812au
sudo make dkms_install
cd ..
rm -rf rtl8812au

echo "[*] Enabling GPSD service..."
sudo systemctl enable gpsd.socket
sudo systemctl start gpsd.socket
sudo gpsd -n "$GPS_DEVICE" -F /var/run/gpsd.sock

echo "[*] Creating log directory..."
sudo mkdir -p "$KISMET_LOG_DIR"
sudo chown "$WARDRIVE_USER:$WARDRIVE_USER" "$KISMET_LOG_DIR"

echo "[*] Configuring AWS credentials..."
mkdir -p /home/$WARDRIVE_USER/.aws
cat <<EOF > /home/$WARDRIVE_USER/.aws/credentials
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
sudo chown -R "$WARDRIVE_USER:$WARDRIVE_USER" /home/$WARDRIVE_USER/.aws

echo "[*] Setting S3 bucket name for sync script..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sed -i "s|S3_BUCKET=.*|S3_BUCKET=\"s3://$S3_BUCKET\"|" "$SCRIPT_DIR/sync-kismet-logs.sh"

if [[ "$SETUP_AP" =~ ^[Yy]$ ]]; then
    echo "[*] Configuring wlan0 as an access point..."
    sudo bash /home/$WARDRIVE_USER/kismet_logs/setup-wifi.sh "$AP_SSID" "$AP_PASS"
fi

echo "[*] Installing systemd services and timers..."
sudo cp /home/$WARDRIVE_USER/kismet_logs/kismet*.service /etc/systemd/system/
sudo cp /home/$WARDRIVE_USER/kismet_logs/kismet*.timer /etc/systemd/system/
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable kismet.service kismet-restart.timer kismet-sync.service

echo "[✓] Setup complete. Rebooting is recommended."
