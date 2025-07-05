#!/bin/bash

set -e

read -p "Enter username for Pi (default: driver): " WARDRIVE_USER
WARDRIVE_USER=${WARDRIVE_USER:-driver}

echo "[*] Cleaning up apt cache..."
sudo apt autoremove --purge -y
sudo apt clean

echo "[*] Disabling unused system services..."
SERVICES_TO_DISABLE=(
    bluetooth.service
    hciuart.service
    avahi-daemon.service
    cups.service
    ModemManager.service
    lightdm.service
    triggerhappy.service
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-enabled --quiet "$svc"; then
        echo "[-] Disabling $svc"
        sudo systemctl disable --now "$svc"
    fi
done

# echo "[*] Removing SSH password login..."
# sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
# sudo systemctl restart ssh

TEMP_DIRS=(
    "$HOME/rtl8812au"
    "$HOME/kismet--pi4"
    "$HOME/Downloads"
)

echo "[*] Clearing history..."

sudo -u "$WARDRIVE_USER" bash -c 'echo "" > ~/.bash_history'
sudo -u "$WARDRIVE_USER" bash -c 'echo "" > ~/.zsh_history'
sudo -u "$WARDRIVE_USER" bash -c 'unset HISTFILE'

MOTD_FILE="/etc/motd"
echo "[*] Updating login MOTD..."
echo "Welcome to WARP 2.0" | sudo tee "$MOTD_FILE" > /dev/null

echo "[*] Removing temp files..."
for dir in "${TEMP_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "[-] Deleting $dir"
        rm -rf "$dir"
    fi

done

echo "[✓] Cleanup complete. Reboot recommended."
