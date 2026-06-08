#!/bin/bash
# Final VPN Enforcement Solution for qBittorrent
# This script ensures VPN is always used for torrent traffic

set -e

NS_NAME="vpn_torrent"
VPN_INTERFACE="tun0"
MAX_WAIT=30

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

wait_for_vpn() {
    log "Waiting for VPN to establish..."
    for i in $(seq 1 $MAX_WAIT); do
        if sudo ip netns exec $NS_NAME ip addr show $VPN_INTERFACE 2>/dev/null | grep -q "inet "; then
            VPN_IP=$(sudo ip netns exec $NS_NAME ip addr show $VPN_INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
            log "VPN established: $VPN_IP"
            return 0
        fi
        sleep 1
    done
    log_error "VPN failed to establish within ${MAX_WAIT}s"
    return 1
}

apply_final_rules() {
    log "Applying final VPN enforcement rules..."

    # Clear existing rules
    sudo ip netns exec $NS_NAME iptables -F
    sudo ip netns exec $NS_NAME iptables -X

    # Default policies - ACCEPT first (will add specific blocks)
    sudo ip netns exec $NS_NAME iptables -P INPUT ACCEPT
    sudo ip netns exec $NS_NAME iptables -P FORWARD ACCEPT
    sudo ip netns exec $NS_NAME iptables -P OUTPUT ACCEPT

    # ALLOW all traffic through VPN interface
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o $VPN_INTERFACE -j ACCEPT
    sudo ip netns exec $NS_NAME iptables -A INPUT -i $VPN_INTERFACE -j ACCEPT

    # BLOCK common P2P ports through non-VPN interface
    P2P_PORTS="6881:6999 51413 1337 4500 6880 8080 9000 9999"
    for port in $P2P_PORTS; do
        sudo ip netns exec $NS_NAME iptables -A OUTPUT -o veth_torrent1 -p tcp --dport $port -j REJECT --reject-with port-unreach
        sudo ip netns exec $NS_NAME iptables -A OUTPUT -o veth_torrent1 -p udp --dport $port -j REJECT --reject-with port-unreach
    done

    # ALLOW essential services through veth (DNS, HTTP, HTTPS, VPN port)
    for port in 53 80 443 4443; do
        sudo ip netns exec $NS_NAME iptables -A OUTPUT -o veth_torrent1 -p tcp --dport $port -j ACCEPT
        sudo ip netns exec $NS_NAME iptables -A OUTPUT -o veth_torrent1 -p udp --dport $port -j ACCEPT
    done

    # BLOCK everything else through veth
    sudo ip netns exec $NS_NAME iptables -A OUTPUT -o veth_torrent1 -j REJECT --reject-with port-unreach

    log "VPN enforcement rules applied"
}

verify_isolation() {
    log "Verifying traffic isolation..."

    # Get external IP
    EXT_IP=$(sudo ip netns exec $NS_NAME timeout 5 curl -s ifconfig.me 2>/dev/null || echo "Failed")

    # Get main system IP
    MAIN_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Failed")

    if [[ "$EXT_IP" == "$MAIN_IP" ]] && [[ "$EXT_IP" != "Failed" ]]; then
        log_error "TRAFFIC LEAK DETECTED! Both IPs match: $EXT_IP"
        return 1
    elif [[ "$EXT_IP" == "Failed" ]]; then
        log_warning "Could not verify external IP (network blocked)"
        return 0
    else
        log "Traffic isolation verified:"
        log "  Main system: $MAIN_IP"
        log "  VPN tunnel:  $EXT_IP"
        return 0
    fi
}

show_status() {
    echo "================================"
    echo "  VPN Enforcement Status"
    echo "================================"
    echo ""

    # Check VPN interface
    echo -n "VPN Interface ($VPN_INTERFACE): "
    if sudo ip netns exec $NS_NAME ip addr show $VPN_INTERFACE 2>/dev/null | grep -q "inet "; then
        VPN_IP=$(sudo ip netns exec $NS_NAME ip addr show $VPN_INTERFACE | grep "inet " | awk '{print $2}')
        echo -e "${GREEN}UP ($VPN_IP)${NC}"
    else
        echo -e "${RED}DOWN${NC}"
    fi

    # Check external IPs
    echo "Main system IP: $(curl -s --max-time 5 ifconfig.me || echo 'Unknown')"
    echo "VPN tunnel IP:  $(sudo ip netns exec $NS_NAME timeout 5 curl -s ifconfig.me || echo 'Unknown')"

    echo ""
    echo "iptables rules:"
    sudo ip netns exec $NS_NAME iptables -L OUTPUT -n -v | grep -E "veth_torrent1|tun0" | head -10
}

# Main
case "${1:-}" in
    start)
        check_root
        log "Starting VPN enforcement..."

        # Start VPN if not running
        if ! sudo ip netns exec $NS_NAME ip addr show $VPN_INTERFACE 2>/dev/null | grep -q "inet "; then
            log "Starting VPN connection..."
            sudo /home/mkinney/repos/server-config/configs/vpn/vpn-torrent.sh start
        fi

        # Wait for VPN
        if wait_for_vpn; then
            apply_final_rules
            verify_isolation
            log "VPN enforcement active!"
        else
            log_error "Failed to establish VPN"
            exit 1
        fi
        ;;
    status)
        show_status
        ;;
    verify)
        check_root
        verify_isolation
        ;;
    *)
        echo "VPN Enforcement for qBittorrent"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  start    - Start VPN and apply enforcement rules"
        echo "  status   - Show current status"
        echo "  verify   - Verify traffic isolation"
        echo ""
        exit 1
        ;;
esac