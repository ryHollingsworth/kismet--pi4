#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

echo "[*] Installing required packages..."
apt update && apt install -y hostapd dnsmasq

echo "[*] Stopping services..."
systemctl stop hostapd
systemctl stop dnsmasq

echo "[*] Configuring static IP for wlan0..."
# Avoid duplicating config
grep -q "interface wlan0" /etc/dhcpcd.conf || cat >> /etc/dhcpcd.conf <<EOF

# Static IP for Wi-Fi AP
interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
EOF

echo "[*] Backing up and creating new dnsmasq.conf..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig 2>/dev/null
cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF

echo "[*] Creating hostapd config..."
cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=PiAP
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=XXXXXXXXXXXXXX
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

echo "[*] Linking hostapd config..."
sed -i 's|#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

echo "[*] Enabling services..."
systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq

echo "[*] Creating static IP fallback systemd service..."

cat > /etc/systemd/system/wlan0-static-ip.service <<EOF
[Unit]
Description=Ensure wlan0 has static IP (192.168.4.1)
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip addr add 192.168.4.1/24 dev wlan0
ExecStartPost=/sbin/ip link set wlan0 up
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable wlan0-static-ip.service

echo "[*] Setup complete! Rebooting in 5 seconds..."
sleep 5
reboot
