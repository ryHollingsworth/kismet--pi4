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

read -p "Enter Kismet GUI username: " KISMET_USER
read -s -p "Enter Kismet GUI password: " KISMET_PASS
echo

GPS_DEVICE="/dev/ttyACM0"
WIFI_INTERFACE="wlan1"
KISMET_LOG_DIR="/home/$WARDRIVE_USER/kismet_logs"

echo "[*] Updating and installing packages..."
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git gpsd gpsd-clients python3-gps kismet dkms build-essential libelf-dev linux-headers-$(uname -r) awscli netfilter-persistent iptables-persistent

echo "[*] Configuring /etc/default/gpsd..."
sudo tee /etc/default/gpsd > /dev/null <<EOF
START_DAEMON="true"
DEVICES="$GPS_DEVICE"
GPSD_OPTIONS="-n"
USBAUTO="false"
EOF

echo "[*] Enabling GPSD service..."
sudo systemctl enable gpsd.socket
sudo systemctl start gpsd.socket

echo "[*] Checking DKMS status for rtl8814au..."

DRIVER_NAME="rtl8814au"
DRIVER_VERSION="5.6.4.2"
DRIVER_CLONE_DIR="/usr/src/${DRIVER_NAME}"
DRIVER_SRC_DIR="/usr/src/${DRIVER_NAME}-${DRIVER_VERSION}"
MODULE_PATH="/lib/modules/$(uname -r)/updates/dkms/88XXau.ko.xz"

DKMS_OUTPUT=$(dkms status ${DRIVER_NAME} 2>/dev/null)

if echo "$DKMS_OUTPUT" | grep -q "installed"; then
    echo "[+] ${DRIVER_NAME} driver already installed via DKMS. Skipping build."
elif echo "$DKMS_OUTPUT" | grep -q "built"; then
    echo "[*] Driver built but not installed."

    if [ -f "$MODULE_PATH" ]; then
        echo "[+] Module file already exists at $MODULE_PATH. Assuming it's already installed. Skipping dkms install."
    else
        echo "[*] Installing built module..."
        dkms install -m ${DRIVER_NAME} -v ${DRIVER_VERSION} || echo "[!] DKMS install failed, but module may already be in place."
    fi
else
    echo "[*] Driver not found in DKMS. Proceeding to clone and build..."

    if [ ! -d "$DRIVER_SRC_DIR" ]; then
        git clone https://github.com/aircrack-ng/rtl8812au.git "$DRIVER_CLONE_DIR"
        mv "$DRIVER_CLONE_DIR" "$DRIVER_SRC_DIR"
    else
        echo "[*] Driver source already exists at $DRIVER_SRC_DIR. Skipping clone."
    fi

    dkms add -m ${DRIVER_NAME} -v ${DRIVER_VERSION}
    dkms build -m ${DRIVER_NAME} -v ${DRIVER_VERSION}
    dkms install -m ${DRIVER_NAME} -v ${DRIVER_VERSION}
fi

echo "[*] Enabling GPSD service..."
sudo systemctl enable gpsd.socket
sudo systemctl start gpsd.socket
sudo gpsd -n "$GPS_DEVICE" -F /var/run/gpsd.sock

echo "[*] Creating log directory..."
sudo mkdir -p "$KISMET_LOG_DIR"
sudo chown "$WARDRIVE_USER:$WARDRIVE_USER" "$KISMET_LOG_DIR"

echo "[*] Applying Kismet Configs ..."
KISMET_CONF_DIR="/home/$WARDRIVE_USER/.kismet"
sudo mkdir -p "$KISMET_CONF_DIR"

sudo tee "$KISMET_CONF_DIR/kismet_httpd.conf" > /dev/null <<EOF
httpd_username=$KISMET_USER
httpd_password=$KISMET_PASS
EOF

sudo chown -R "$WARDRIVE_USER:$WARDRIVE_USER" "$KISMET_CONF_DIR"
sudo chmod 700 "$KISMET_CONF_DIR"
sudo chmod 600 "$KISMET_CONF_DIR/kismet_httpd.conf"

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
    sudo bash "$SCRIPT_DIR/setup-wifi.sh" "$AP_SSID" "$AP_PASS"
fi

echo "[*] Copying core .sh scripts to /usr/local/bin..."
sudo cp "$SCRIPT_DIR"/start-kismet.sh /usr/local/bin/
sudo cp "$SCRIPT_DIR"/sync-kismet-logs.sh /usr/local/bin/
sudo cp "$SCRIPT_DIR/check-network-status.sh" /usr/local/bin/
sudo chmod +x /usr/local/bin/start-kismet.sh /usr/local/bin/sync-kismet-logs.sh /usr/local/bin/check-network-status.sh

echo "[*] Applying Kismet config files..."
sudo cp "$SCRIPT_DIR"/kismet*.conf /etc/kismet/

echo "[*] Installing systemd services and timers..."
sudo cp "$SCRIPT_DIR"/kismet*.service /etc/systemd/system/
sudo cp "$SCRIPT_DIR"/kismet*.timer /etc/systemd/system/

echo "[*] Updating kismet.service to run as $WARDRIVE_USER..."
if grep -q "^User=" /etc/systemd/system/kismet.service; then
    sudo sed -i "s/^User=.*/User=$WARDRIVE_USER/" /etc/systemd/system/kismet.service
else
    sudo sed -i "/^\[Service\]/a User=$WARDRIVE_USER" /etc/systemd/system/kismet.service
fi

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable kismet.service kismet-restart.timer kismet-sync.service

echo "[*] Setting $WARDRIVE_USER permissions"
sudo usermod -aG kismet "$WARDRIVE_USER"

echo "[*] Disabling NetworkManager..."
systemctl disable NetworkManager
systemctl stop NetworkManager

echo "[*] Setting static DNS resolver..."
rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
sudo chattr +i /etc/resolv.conf

echo "[✓] Setup complete. Rebooting is recommended."
