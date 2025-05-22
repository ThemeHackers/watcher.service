#!/bin/bash


set -e  

SERVICE_NAME="watcher.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
SCRIPT_NAME="the_watcher.sh"
SCRIPT_PATH="/usr/local/bin/$SCRIPT_NAME"


if [[ "$EUID" -ne 0 ]]; then
  echo "Please run this script as root (e.g., with sudo)."
  exit 1
fi

echo "[+] Installing $SERVICE_NAME..."
install -m 644 "$SERVICE_NAME" "$SERVICE_PATH"

echo "[+] Installing $SCRIPT_NAME..."
install -m 755 "$SCRIPT_NAME" "$SCRIPT_PATH"

echo "[+] Reloading systemd daemon..."
systemctl daemon-reload

echo "[+] Enabling $SERVICE_NAME to start on boot..."
systemctl enable "$SERVICE_NAME"

echo "[+] Starting $SERVICE_NAME..."
systemctl start "$SERVICE_NAME"

echo "[+] Showing $SERVICE_NAME status:"
systemctl status "$SERVICE_NAME" --no-pager

echo "[✓] Installation complete!"

exit 0
