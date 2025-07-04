#!/bin/bash

#####################
# Configurable Vars #
#####################
GPS_DEVICE="/dev/ttyACM0"
WIFI_INTERFACE="wlan1"
REQUIRED_DRIVER="rtl88XXau"
EXPECTED_GPS_MODE=3
LOGFILE="/home/driver/kismet_logs/daemon.log"
KISMET_CMD="kismet -c ${WIFI_INTERFACE} --no-ncurses" #ncurses is a prompt to use GUI and unnecessary
LOCKFILE="/tmp/kismet-sync.lock"



#####################
# Helper Functions  #
#####################
log()    { echo "[$(date '+%F %T')] $1" | tee -a "$LOGFILE"; }
info()   { echo -e "\e[34m[*] $1\e[0m"; log "$1"; }
success(){ echo -e "\e[32m[+] $1\e[0m"; log "$1"; }
warn()   { echo -e "\e[33m[!] $1\e[0m"; log "$1"; }
fail()   { echo -e "\e[31m[-] $1\e[0m"; log "$1"; exit 1; }

#####################
# LED Signal        #
#####################
function led_signal() {
    echo none | sudo tee /sys/class/leds/ACT/trigger >/dev/null
    echo 1    | sudo tee /sys/class/leds/ACT/brightness >/dev/null
    ( sleep 120 && echo mmc0 | sudo tee /sys/class/leds/ACT/trigger >/dev/null ) &
}

#####################
# Preflight Checks  #
#####################
info "Starting preflight checks..."

if ! ip link show "$WIFI_INTERFACE" > /dev/null 2>&1; then
    fail "Wi-Fi interface '$WIFI_INTERFACE' not found."
fi

DRIVER=$(ethtool -i "$WIFI_INTERFACE" 2>/dev/null | grep driver | awk '{print $2}')
[[ "$DRIVER" == "$REQUIRED_DRIVER" ]] || fail "Expected driver '$REQUIRED_DRIVER', found '$DRIVER'."

if [ ! -e "$GPS_DEVICE" ]; then
    fail "GPS device '$GPS_DEVICE' not detected."
fi

GPS_MODE=$(gpspipe -w -n 30 | grep '"class":"TPV"' | grep -Po '"mode":\K[0-9]' | head -n1)
[[ "$GPS_MODE" == "$EXPECTED_GPS_MODE" ]] && success "GPS 3D fix acquired." || warn "GPS mode $GPS_MODE (not 3D fix)"

#####################
# Start Kismet      #
#####################
info "Launching Kismet..."

# If internet is up, don't start
if ping -q -c1 8.8.8.8 >/dev/null 2>&1; then
    echo "[!] Internet detected. Not starting Kismet."
    exit 0
fi

# If syncing (lockfile exists), don't start
if [ -f "$LOCKFILE" ]; then
    echo "[!] Sync in progress. Not starting Kismet."
    exit 0
fi


led_signal
cd /home/driver/kismet_logs
exec sudo -u driver $KISMET_CMD
