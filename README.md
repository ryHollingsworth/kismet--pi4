
# WARP 2.0: Automated Wardriving Kit for Raspberry Pi

WARP 2.0 is an automated Kismet-based wardriving deployment tailored for Raspberry Pi 4/5 running Kali Linux ARM64. WARP 2.0 uses Kismet, GPS logging, and cloud integration (AWS S3) to function as a lean, power-efficient mobile wireless recon utility.

## Features

- 📡 **Wireless Packet Capture** via Alfa AWUS036ACH/RTL8814AU chipset
- 🛰️ **GPS Logging** with GPSD and USB GPS receivers
- ☁️ **Cloud Sync** to AWS S3 with hash verification
- 🧠 **Smart Autostart**: Automatically launches Kismet when offline
- 🔒 **Basic Web UI Auth** with user-defined login for Kismet dashboard
- ⚙️ **System Optimizations** for power saving and persistent logging
- 🚀 **One-Command Setup** with full automation via shell script (experimental)

## Requirements

- Raspberry Pi 4 or 5 (ARM64 Kali Linux recommended)
- USB Wi-Fi adapter (RTL8814AU recommended, like Alfa AWUS1900)
- USB GPS Receiver (e.g UBX-G7020KT )
- 16GB+ microSD card
- External battery or mobile power supply
- AWS S3 bucket and credentials (for cloud sync)

## Installation

1. Flash **Kali ARM64** to your SD card.
2. Create a user (default: `driver`).
3. Clone this repository and run:

```bash
chmod +x \*.sh
sudo ./install.sh
```

4. Follow the prompts to configure your S3 bucket, GPS device, and GUI credentials.

## Maintenance & Cleanup

After install, run the post-install cleanup to slim the system:

```bash
chmod +x post_install_cleanup.sh
sudo ./post_install_cleanup.sh
```

This disables unnecessary services, clears logs/histories, and prepares the system for efficient field use.

## Log Syncing

Logs are rotated and synced automatically when an internet connection becomes available. A systemd daemon monitors network state and performs uploads with hash verification.

## Kismet Access

If enabled during intial setup the wlan0 interface creates a management Wi-Fi Access Point(AP) allowing operator to access the Kismet GUI or SSH into the device.

- Dashboard: `http://<Pi_IP>:2501`
- Credentials are saved to `~/.kismet/kismet_httpd.conf` after setup.

## Roadmap / Future Enhancements

### 🔐 WireGuard VPN Integration

Future versions will support secure VPN tunnels via **WireGuard**, allowing for encrypted real-time access to logs or remote administration while on the road.

### 📶 Sixfab Mobile Cellular Modem Support

Integrate with **Sixfab LTE cellular HATs** to provide mobile internet for cloud sync and remote access in the field, without dependency on Wi-Fi APs.

## Troubleshooting

- Ensure the GPS device is listed at `/dev/ttyACM0` and detected by gpsd.
- To manually bring down Wi-Fi: `sudo ip link set eth0 down`
- Verify S3 upload: `aws s3 ls s3://<your-bucket-name>`

## Credits

Original project foundation by [Kismet](https://www.kismetwireless.net/). RTL8814AU driver by aircrack-ng.

---

**Welcome to WARP 2.0.** Optimize, observe, and outmaneuver.
