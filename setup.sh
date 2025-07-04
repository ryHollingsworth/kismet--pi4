#!/bin/bash

# install-kismet-airgap.sh
# One-time setup script to configure Kismet airgap logging rig on Raspberry Pi

set -e

echo "== Kismet Airgap Logger Setup =="

read -p "Enter Pi username [driver]: " PI_USER
PI_USER=${PI_USER:-driver}

read -p "Do you want to configure wlan0 as an Access Point? (y/n): " USE_AP
if [[ "$USE_AP" == "y" || "$USE_AP" == "Y" ]]; then
    read -p "Enter SSID for AP: " AP_SSID
    read -p "Enter password for AP: " AP_PASS
fi

read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -p "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
read -p "Enter S3 Bucket name: " S3_BUCKET

echo "[1/7] Updating system and installing dependencies..."
sudo apt-get update
sudo apt-get install -y awscli gpsd gpsd-clients ethtool dnsmasq hostapd

echo "[2/7] Configuring AWS CLI for $PI_USER..."
sudo -u $PI_USER mkdir -p /home/$PI_USER/.aws
cat <<EOF | sudo -u $PI_USER tee /home/$PI_USER/.aws/credentials > /dev/null
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF

cat <<EOF | sudo -u $PI_USER tee /home/$PI_USER/.aws/config > /dev/null
[default]
region = us-east-1
output = json
EOF

echo "[3/7] Creating required directories and setting permissions..."
sudo mkdir -p /home/$PI_USER/kismet_logs
sudo chown -R $PI_USER:$PI_USER /home/$PI_USER/kismet_logs

echo "[4/7] Installing Kismet configuration and service files..."
cd "$(dirname "$0")/kismet--airgap-main"
sudo cp kismet.conf kismet_logging.conf /etc/kismet/
sudo cp *.service *.timer /etc/systemd/system/
sudo cp start-kismet.sh sync-kismet-logs.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/*.sh

echo "[5/7] Enabling Kismet systemd services and timers..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable kismet.service
sudo systemctl enable kismet-restart.timer
sudo systemctl enable kismet-sync.service

echo "[6/7] Optional: Configuring wlan0 as AP..."
if [[ "$USE_AP" == "y" || "$USE_AP" == "Y" ]]; then
    export PI_USER AP_SSID AP_PASS
    chmod +x setup-wifi.sh
    sudo ./setup-wifi.sh "$PI_USER" "$AP_SSID" "$AP_PASS"
fi

echo "[7/7] Setup complete. Rebooting system to apply all changes..."
sudo reboot
