#!/bin/bash
# VPN Killswitch for qBittorrent Namespace
# Blocks all traffic if VPN is not active
# Usage: ./vpn-killswitch.sh {install|enable|disable|status|check}

set -e

NS_NAME="vpn_torrent"
NS_IFACE="veth_torrent1"
VPN_IFACE="tun+"  # Matches tun0, tun1, tun2, etc.
MAIN_IFACE="enp1s0"
LOCAL_NET="10.201.1.0/24"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script requires root privileges"
        exit 1
    fi
}

# Check if VPN interface exists in namespace
check_vpn() {
    if sudo ip netns exec $NS_NAME ip addr show $VPN_IFACE &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Install killswitch rules
install_rules() {
    check_root
    log "Installing VPN killswitch rules..."

    # Clear existing rules
    sudo ip netns exec $NS_NAME iptables -F
    sudo ip netns exec $NS_NAME iptables -X
    sudo ip netns exec $NS_NAME iptables -t nat -F

    # Default policies - DROP everything
    sudo ip netns exec $NS_NAME iptables -P INPUT DROP
    sudo ip netns exec $NS_NAME iptables -P FORWARD DROP
    sudo ip netns exec $NS_NAME iptables -P OUTPUT DROP

    # Allow loopback
    sudo ip netns exec $NS_NAME iptables -A INPUT -i lo -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established connections
    sudo ip netns exec $NS_NAME iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # ALLOW DNS through both interfaces (DNS needed for VPN setup)
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -p udp --dport 53 -o $VPN_IFACE -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -p udp --dport 53 -o $NS_IFACE -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -p tcp --dport 53 -o $VPN_IFACE -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -p tcp --dport 53 -o $NS_IFACE -j ACCEPT

    # ALLOW VPN traffic (UDP 4443 for OpenVPN)
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -p udp --dport 4443 -o $NS_IFACE -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A INPUT -p udp --sport 4443 -i $NS_IFACE -j ACCEPT

    # ALLOW qBittorrent WebUI (local access only)
    sudo ip netns exec $NS_NAME iptables -A INPUT -p tcp --dport 8080 -s 10.201.1.1 -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -p tcp --sport 8080 -d 10.201.1.1 -j ACCEPT

    # BLOCK all other traffic through veth interface (non-VPN)
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $NS_IFACE -j DROP
    sudo ip netns exec $NS_NAME iptables -A INPUT -i $NS_IFACE -j DROP

    # ALLOW all traffic through VPN interface
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $VPN_IFACE -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A INPUT -i $VPN_IFACE -j ACCEPT

    log "Killswitch rules installed!"
    log "Traffic BLOCKED unless VPN is active"
}

# Enable killswitch (install and save)
enable_killswitch() {
    install_rules
    log "Killswitch enabled - VPN enforced!"
}

# Disable killswitch (restore default accept)
disable_killswitch() {
    check_root
    log "Disabling killswitch..."

    sudo ip netns exec $NS_NAME iptables -F
    sudo ip netns exec $NS_NAME iptables -X
    sudo ip netns exec $NS_NAME iptables -t nat -F
    sudo ip netns exec $NS_NAME iptables -P INPUT ACCEPT
    sudo ip netns exec $NS_NAME iptables -P FORWARD ACCEPT
    sudo ip netns exec $NS_NAME iptables -P OUTPUT ACCEPT

    log_warning "Killswitch disabled - traffic allowed without VPN!"
}

# Show status
show_status() {
    echo "================================"
    echo "  VPN Killswitch Status"
    echo "================================"
    echo ""

    # Check namespace exists
    if ! ip netns list | grep -q "$NS_NAME"; then
        log_error "Namespace $NS_NAME not found"
        exit 1
    fi

    # Check VPN interface
    echo -n "VPN Interface ($VPN_IFACE): "
    if sudo ip netns exec $NS_NAME ip addr show $VPN_IFACE &>/dev/null; then
        IP=$(sudo ip netns exec $NS_NAME ip addr show $VPN_IFACE | grep "inet " | awk '{print $2}')
        echo -e "${GREEN}UP ($IP)${NC}"
    else
        echo -e "${RED}DOWN${NC}"
    fi

    # Check external IP
    echo -n "External IP: "
    EXT_IP=$(sudo ip netns exec $NS_NAME curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Failed")
    echo "$EXT_IP"

    # Check iptables
    echo -n "Killswitch Rules: "
    POLICY=$(sudo ip netns exec $NS_NAME iptables -L INPUT | grep "Chain INPUT" | awk '{print $4}')
    if [[ "$POLICY" == "DROP" ]]; then
        echo -e "${GREEN}ACTIVE${NC}"
    else
        echo -e "${RED}INACTIVE${NC}"
    fi

    echo ""
    sudo ip netns exec $NS_NAME iptables -L -n -v
}

# Quick check
check_status() {
    if check_vpn; then
        echo "VPN_UP"
        exit 0
    else
        echo "VPN_DOWN"
        exit 1
    fi
}

# Main
case "${1:-}" in
    install)
        install_rules
        ;;
    enable)
        enable_killswitch
        ;;
    disable)
        disable_killswitch
        ;;
    status)
        show_status
        ;;
    check)
        check_status
        ;;
    *)
        echo "VPN Killswitch for qBittorrent"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  install   - Install iptables killswitch rules"
        echo "  enable    - Enable killswitch (VPN required for traffic)"
        echo "  disable   - Disable killswitch (allow all traffic)"
        echo "  status    - Show current status"
        echo "  check     - Quick check (exit 0 if VPN up, 1 if down)"
        echo ""
        exit 1
        ;;
esac