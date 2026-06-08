#!/bin/bash
# Install VPN monitoring service

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script requires root privileges"
    echo "Please run: sudo $0"
    exit 1
fi

log "Installing VPN monitoring service..."

# Copy service file
sudo cp /home/mkinney/repos/qBittorrent/docs/vpn-monitor.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable service
sudo systemctl enable vpn-monitor.service

# Start service
sudo systemctl start vpn-monitor.service

# Wait and check status
sleep 3

if sudo systemctl is-active --quiet vpn-monitor.service; then
    log "✓ VPN monitoring service active"
    log ""
    log "To check monitoring logs:"
    log "  sudo journalctl -u vpn-monitor.service -f"
    log ""
    log "To check service status:"
    log "  sudo systemctl status vpn-monitor.service"
else
    log_error "✗ VPN monitoring service failed to start"
    sudo systemctl status vpn-monitor.service
    exit 1
fi