#!/bin/bash
# Simplified VPN Killswitch - Only blocks P2P traffic without VPN
# This version allows VPN setup while blocking torrent leaks

set -e

NS_NAME="vpn_torrent"
NS_IFACE="veth_torrent1"
VPN_IFACE="tun+"  # Matches tun0, tun1, tun2, etc.
VPN_PORT="4443"

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

# Install simplified killswitch rules
install_rules() {
    check_root
    log "Installing simplified VPN killswitch rules..."

    # Clear existing rules
    sudo ip netns exec $NS_NAME iptables -F
    sudo ip netns exec $NS_NAME iptables -X
    sudo ip netns exec $NS_NAME iptables -t nat -F

    # Default policies - ACCEPT (we'll block specific traffic)
    sudo ip netns exec $NS_NAME iptables -P INPUT ACCEPT
    sudo ip netns exec $NS_NAME iptables -P FORWARD ACCEPT
    sudo ip netns exec $NS_NAME iptables -P OUTPUT ACCEPT

    # BLOCK all P2P traffic through non-VPN interface (common BitTorrent ports)
    for port in 6881:6999 51413 1337 4500; do
        sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $NS_IFACE -p tcp --dport $port -j REJECT --reject-with port-unreach
        sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $NS_IFACE -p udp --dport $port -j REJECT --reject-with port-unreach
    done

    # BLOCK all outgoing traffic through veth EXCEPT:
    # - DNS (53)
    # - VPN port (4443)
    # - HTTP/HTTPS (80/443) for WebUI access
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $NS_IFACE -p udp --dport 53 -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $NS_IFACE -p tcp --dport 53 -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $NS_IFACE -p udp --dport $VPN_PORT -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $NS_IFACE -p tcp --dport $VPN_PORT -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $NS_IFACE -p tcp --dport 80 -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $NS_IFACE -p tcp --dport 443 -j ACCEPT

    # BLOCK everything else through veth
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $NS_IFACE -j REJECT --reject-with port-unreach
    sudo ip netns exec $NS_NAME iptables -A INPUT -i $NS_IFACE -j DROP

    # ALLOW all traffic through VPN interface
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $VPN_IFACE -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A INPUT -i $VPN_IFACE -j ACCEPT

    log "Killswitch rules installed! P2P traffic blocked without VPN"
}

# Enable killswitch
enable_killswitch() {
    install_rules
    log "Killswitch enabled - P2P traffic blocked without VPN!"
}

# Disable killswitch
disable_killswitch() {
    check_root
    log "Disabling killswitch..."

    sudo ip netns exec $NS_NAME iptables -F
    sudo ip netns exec $NS_NAME iptables -X
    sudo ip netns exec $NS_NAME iptables -t nat -F
    sudo ip netns exec $NS_NAME iptables -P INPUT ACCEPT
    sudo ip netns exec $NS_NAME iptables -P FORWARD ACCEPT
    sudo ip netns exec $NS_NAME iptables -P OUTPUT ACCEPT

    log_warning "Killswitch disabled - all traffic allowed!"
}

# Show status
show_status() {
    echo "================================"
    echo "  VPN Killswitch Status"
    echo "================================"
    echo ""

    if ! ip netns list | grep -q "$NS_NAME"; then
        log_error "Namespace $NS_NAME not found"
        exit 1
    fi

    # Check VPN interface
    echo -n "VPN Interface ($VPN_IFACE): "
    if sudo ip netns exec $NS_NAME ip addr show $VPN_IFACE &>/dev/null; then
        IP=$(sudo ip netns exec $NS_NAME ip addr show $VPN_IFACE 2>/dev/null | grep "inet " | head -1 | awk '{print $2}')
        echo -e "${GREEN}UP ($IP)${NC}"
    else
        echo -e "${RED}DOWN${NC}"
    fi

    # Check external IP
    echo -n "External IP: "
    EXT_IP=$(sudo ip netns exec $NS_NAME timeout 5 curl -s ifconfig.me 2>/dev/null || echo "Unknown")
    echo "$EXT_IP"

    echo ""
    sudo ip netns exec $NS_NAME iptables -L -n -v
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
    *)
        echo "Simplified VPN Killswitch for qBittorrent"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  install   - Install iptables killswitch rules"
        echo "  enable    - Enable killswitch"
        echo "  disable   - Disable killswitch"
        echo "  status    - Show current status"
        echo ""
        exit 1
        ;;
esac