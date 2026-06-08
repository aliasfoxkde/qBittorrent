#!/bin/bash
# Install updated systemd services for VPN enforcement
# This replaces the existing services with improved versions

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

log "Installing updated systemd services for qBittorrent VPN enforcement..."

# Backup existing services
log "Backing up existing services..."
sudo cp /etc/systemd/system/qbittorrent-vpn-namespace.service /etc/systemd/system/qbittorrent-vpn-namespace.service.backup 2>/dev/null || true
sudo cp /etc/systemd/system/qbittorrent-vpn.service /etc/systemd/system/qbittorrent-vpn.service.backup 2>/dev/null || true

# Copy new services
log "Installing new service files..."
sudo cp /home/mkinney/repos/qBittorrent/docs/qbittorrent-vpn-namespace.service /etc/systemd/system/
sudo cp /home/mkinney/repos/qBittorrent/docs/qbittorrent-vpn.service /etc/systemd/system/

# Reload systemd
log "Reloading systemd daemon..."
sudo systemctl daemon-reload

# Enable services
log "Enabling services..."
sudo systemctl enable qbittorrent-vpn-namespace.service
sudo systemctl enable qbittorrent-vpn.service

# Stop existing services
log "Stopping existing services..."
sudo systemctl stop qbittorrent-vpn.service 2>/dev/null || true
sudo systemctl stop qbittorrent-vpn-namespace.service 2>/dev/null || true

# Start new services
log "Starting new VPN enforcement services..."
sudo systemctl start qbittorrent-vpn-namespace.service
sudo systemctl start qbittorrent-vpn.service

# Wait for services to start
sleep 5

# Check status
log "Checking service status..."
if sudo systemctl is-active --quiet qbittorrent-vpn-namespace.service; then
    log "✓ VPN namespace service active"
else
    log_error "✗ VPN namespace service failed to start"
    sudo systemctl status qbittorrent-vpn-namespace.service
fi

if sudo systemctl is-active --quiet qbittorrent-vpn.service; then
    log "✓ qBittorrent VPN service active"
else
    log_error "✗ qBittorrent VPN service failed to start"
    sudo systemctl status qbittorrent-vpn.service
fi

log ""
log "Installation complete!"
log ""
log "To check status:"
log "  sudo systemctl status qbittorrent-vpn-namespace.service"
log "  sudo systemctl status qbittorrent-vpn.service"
log ""
log "To verify VPN enforcement:"
log "  sudo /home/mkinney/repos/qBittorrent/docs/vpn-enforce.sh status"