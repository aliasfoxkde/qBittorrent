#!/bin/bash
# Verify VPN enforcement auto-start configuration

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

log "Verifying VPN enforcement auto-start configuration..."
log ""

# Check if services are enabled
log "Checking service enablement..."
services=(
    "qbittorrent-vpn-namespace.service"
    "qbittorrent-vpn.service"
    "vpn-monitor.service"
)

all_enabled=true
for service in "${services[@]}"; do
    if sudo systemctl is-enabled "$service" &>/dev/null; then
        log "✓ $service is enabled"
    else
        log_error "✗ $service is NOT enabled"
        all_enabled=false
    fi
done

log ""

# Check service order
log "Checking service dependencies..."
if sudo systemctl show qbittorrent-vpn.service | grep -q "Requires=qbittorrent-vpn-namespace.service"; then
    log "✓ qBittorrent requires VPN namespace service"
else
    log_warning "qBittorrent may not require VPN namespace service"
fi

if sudo systemctl show vpn-monitor.service | grep -q "Requires=qbittorrent-vpn-namespace.service"; then
    log "✓ VPN monitor requires VPN namespace service"
else
    log_warning "VPN monitor may not require VPN namespace service"
fi

log ""

# Test startup sequence
log "Testing startup sequence (dry run)..."
sudo systemd-analyze verify qbittorrent-vpn-namespace.service 2>/dev/null && log "✓ VPN namespace service configuration valid" || log_error "✗ VPN namespace service has issues"
sudo systemd-analyze verify qbittorrent-vpn.service 2>/dev/null && log "✓ qBittorrent service configuration valid" || log_error "✗ qBittorrent service has issues"
sudo systemd-analyze verify vpn-monitor.service 2>/dev/null && log "✓ VPN monitor service configuration valid" || log_error "✗ VPN monitor service has issues"

log ""

# Final status
if [[ "$all_enabled" == true ]]; then
    log "✅ Auto-start configuration complete!"
    log ""
    log "Services will start in this order on boot:"
    log "  1. qbittorrent-vpn-namespace.service (VPN + enforcement)"
    log "  2. qbittorrent-vpn.service (qBittorrent in namespace)"
    log "  3. vpn-monitor.service (continuous monitoring)"
    log ""
    log "To simulate boot startup:"
    log "  sudo /home/mkinney/repos/qBittorrent/docs/vpn-enforce.sh start"
    log "  sudo systemctl start qbittorrent-vpn.service"
    log "  sudo systemctl start vpn-monitor.service"
else
    log_error "❌ Some services are not enabled for auto-start"
    log ""
    log "To enable all services:"
    log "  sudo systemctl enable qbittorrent-vpn-namespace.service"
    log "  sudo systemctl enable qbittorrent-vpn.service"
    log "  sudo systemctl enable vpn-monitor.service"
    exit 1
fi