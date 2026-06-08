#!/bin/bash
# VPN Monitor - Ensures qBittorrent only runs with active VPN
# Monitors VPN connection and restarts services if needed

set -e

NS_NAME="vpn_torrent"
VPN_IFACE="tun0"
ENFORCEMENT_SCRIPT="/home/mkinney/repos/qBittorrent/docs/vpn-enforce.sh"
CHECK_INTERVAL=30

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

check_vpn() {
    if sudo ip netns exec $NS_NAME ip addr show $VPN_IFACE &>/dev/null; then
        return 0
    else
        return 1
    fi
}

verify_vpn_traffic() {
    # Test that traffic actually goes through VPN
    LOCAL_IP=$(sudo ip netns exec $NS_NAME ip addr show $VPN_IFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [[ -z "$LOCAL_IP" ]]; then
        return 1
    fi

    # Test external IP
    EXT_IP=$(sudo ip netns exec $NS_NAME timeout 5 curl -s ifconfig.me 2>/dev/null || echo "")
    if [[ -z "$EXT_IP" ]]; then
        return 1
    fi

    # Get main system IP
    MAIN_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "")

    # IPs should be different (VPN vs non-VPN)
    if [[ "$EXT_IP" == "$MAIN_IP" ]]; then
        log_warning "External IP matches main system - VPN may not be isolated"
        return 1
    fi

    return 0
}

restart_vpn() {
    log "Restarting VPN enforcement..."
    sudo systemctl restart qbittorrent-vpn-namespace.service
    sleep 10
}

enforce_killswitch() {
    log "Checking VPN enforcement..."
    sudo $ENFORCEMENT_SCRIPT verify 2>/dev/null || true
}

monitor_loop() {
    log "Starting VPN monitoring (checking every ${CHECK_INTERVAL}s)..."

    while true; do
        # Check VPN interface exists
        if ! check_vpn; then
            log_error "VPN interface $VPN_IFACE not found!"
            restart_vpn
            sleep 30
            continue
        fi

        # Verify VPN is actually routing traffic
        if ! verify_vpn_traffic; then
            log_error "VPN traffic verification failed!"
            restart_vpn
            sleep 30
            continue
        fi

        # Ensure killswitch is active
        POLICY=$(sudo ip netns exec $NS_NAME iptables -L INPUT 2>/dev/null | grep "Chain INPUT" | awk '{print $4}' || echo "")
        if [[ "$POLICY" != "DROP" ]]; then
            log_warning "Killswitch not active, enabling..."
            enforce_killswitch
        fi

        # VPN looks good
        EXT_IP=$(sudo ip netns exec $NS_NAME timeout 5 curl -s ifconfig.me 2>/dev/null || echo "Unknown")
        log "VPN OK - External IP: $EXT_IP"

        sleep $CHECK_INTERVAL
    done
}

# Main
case "${1:-}" in
    monitor)
        monitor_loop
        ;;
    check)
        if check_vpn && verify_vpn_traffic; then
            log "VPN is working correctly"
            exit 0
        else
            log_error "VPN check failed"
            exit 1
        fi
        ;;
    *)
        echo "VPN Monitor for qBittorrent"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  monitor   - Start continuous monitoring"
        echo "  check     - One-time VPN check"
        echo ""
        exit 1
        ;;
esac