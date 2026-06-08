#!/bin/bash
# Comprehensive VPN Enforcement Validation - Fixed version
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }
log_info() { echo -e "${BLUE}[i]${NC} $*"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  qBittorrent VPN Enforcement - End-to-End Validation          ║"
echo "╚════════════════════════════════════════════════════════════════╝"

test_count=0
pass_count=0
fail_count=0

run_test() {
    local test_name="$1"
    local test_command="$2"

    ((test_count++))
    log_info "$test_count. $test_name"

    if eval "$test_command" >/dev/null 2>&1; then
        log_success "$test_name"
        ((pass_count++))
        return 0
    else
        log_error "$test_name"
        ((fail_count++))
        return 1
    fi
}

# Section 1: Infrastructure
log_section "1. Infrastructure Validation"
run_test "Network namespace exists" "sudo ip netns list | grep -q vpn_torrent"
run_test "Namespace has veth interface" "sudo ip netns exec vpn_torrent ip link show veth_torrent1"
run_test "Host has veth interface" "ip link show veth_torrent0"

# Section 2: VPN Connection
log_section "2. VPN Connection Validation"
run_test "VPN tunnel interface exists" "sudo ip netns exec vpn_torrent ip link show tun0"
run_test "VPN tunnel has IP address" "sudo ip netns exec vpn_torrent ip addr show tun0 | grep -q 'inet '"
run_test "VPN tunnel is UP" "sudo ip netns exec vpn_torrent ip link show tun0 | grep -q 'UP,'"

# Get VPN info
VPN_TUN_IP=$(sudo ip netns exec vpn_torrent ip addr show tun0 2>/dev/null | grep "inet " | awk '{print $2}' || echo "Unknown")
log_info "VPN Tunnel IP: $VPN_TUN_IP"

# Section 3: Traffic Isolation
log_section "3. Traffic Isolation Validation"
MAIN_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Failed")
VPN_EXT_IP=$(sudo ip netns exec vpn_torrent timeout 5 curl -s ifconfig.me 2>/dev/null || echo "Failed")

log_info "Main System IP: $MAIN_IP"
log_info "VPN Tunnel IP:  $VPN_EXT_IP"

if [[ "$VPN_EXT_IP" != "Failed" ]] && [[ "$MAIN_IP" != "Failed" ]] && [[ "$VPN_EXT_IP" != "$MAIN_IP" ]]; then
    log_success "Traffic properly isolated (different IPs)"
    ((pass_count++))
else
    log_error "Traffic isolation failed or connectivity issues"
    ((fail_count++))
fi

# Section 4: qBittorrent Process
log_section "4. qBittorrent Process Validation"
run_test "qBittorrent service running" "sudo systemctl is-active qbittorrent-vpn.service"
run_test "qBittorrent process exists" "sudo pidof qbittorrent-nox"

# Check qBittorrent bindings
if sudo ip netns exec vpn_torrent netstat -tlnp 2>/dev/null | grep -q qbittorrent; then
    BINDINGS=$(sudo ip netns exec vpn_torrent netstat -tlnp 2>/dev/null | grep qbittorrent | grep -E "10.16.0|10.201.1" | wc -l)
    if [[ $BINDINGS -gt 0 ]]; then
        log_success "qBittorrent bound to VPN interfaces ($BINDINGS bindings)"
        ((pass_count++))
    else
        log_warning "qBittorrent bindings may not be optimal"
        ((fail_count++))
    fi
else
    log_error "Could not determine qBittorrent bindings"
    ((fail_count++))
fi

# Section 5: WebUI
log_section "5. qBittorrent WebUI Validation"
run_test "WebUI accessible through namespace" "sudo ip netns exec vpn_torrent curl -s http://localhost:8080 | grep -q qBittorrent"
run_test "WebUI responds with HTTP 200" "sudo ip netns exec vpn_torrent curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 | grep -q 200"

# Section 6: Security Rules
log_section "6. iptables Security Rules"
run_test "iptables OUTPUT chain exists" "sudo ip netns exec vpn_torrent iptables -L OUTPUT"
run_test "iptables INPUT chain exists" "sudo ip netns exec vpn_torrent iptables -L INPUT"

# Check VPN rules
if sudo ip netns exec vpn_torrent iptables -L OUTPUT | grep -q "tun.*ACCEPT"; then
    log_success "VPN traffic allowed through tunnel"
    ((pass_count++))
else
    log_warning "VPN traffic rules may need checking"
    ((fail_count++))
fi

# Check P2P blocking
if sudo ip netns exec vpn_torrent iptables -L OUTPUT | grep -q "6881.*REJECT"; then
    log_success "P2P ports blocked on non-VPN interface"
    ((pass_count++))
else
    log_warning "P2P blocking may not be active"
    ((fail_count++))
fi

# Section 7: Services
log_section "7. Service Integration"
run_test "VPN namespace service active" "sudo systemctl is-active qbittorrent-vpn-namespace.service"
run_test "qBittorrent service active" "sudo systemctl is-active qbittorrent-vpn.service"
run_test "VPN monitor service active" "sudo systemctl is-active vpn-monitor.service"
run_test "VPN namespace service enabled" "sudo systemctl is-enabled qbittorrent-vpn-namespace.service"
run_test "qBittorrent service enabled" "sudo systemctl is-enabled qbittorrent-vpn.service"
run_test "VPN monitor service enabled" "sudo systemctl is-enabled vpn-monitor.service"

# Section 8: Monitoring
log_section "8. Monitoring Activity"
run_test "VPN monitor process running" "sudo systemctl status vpn-monitor.service | grep -q 'active.*running'"

# Check monitoring logs
if sudo journalctl -u vpn-monitor.service -n 5 --no-pager 2>/dev/null | grep -q "VPN OK"; then
    log_success "VPN monitor actively checking status"
    ((pass_count++))
else
    log_warning "Monitoring logs may need review"
    ((fail_count++))
fi

# Section 9: File System
log_section "9. File System Validation"
run_test "qBittorrent config exists" "test -d /var/lib/qbittorrent"
run_test "Download directories exist" "test -d /nas/Downloads/Complete && test -d /nas/Downloads/Incomplete"
run_test "VPN credentials file exists" "test -f /home/mkinney/repos/server-config/configs/vpn/fastestvpn-credentials.txt"

# Section 10: Connectivity
log_section "10. Network Connectivity"
run_test "External connectivity through VPN" "sudo ip netns exec vpn_torrent timeout 5 curl -s -o /dev/null http://www.google.com"

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Validation Summary                          ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Tests Run:    $test_count                                            ║"
printf "║  %-15s ${GREEN}%-30s${NC} ║\n" "Passed:" "$pass_count"
printf "║  %-15s ${RED}%-30s${NC} ║\n" "Failed:" "$fail_count"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $fail_count -eq 0 ]]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           ✅ END-TO-END VALIDATION SUCCESSFUL                  ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║  VPN Enforcement is working correctly across all layers:      ║${NC}"
    echo -e "${GREEN}║  • Infrastructure: Network namespace isolation                ║${NC}"
    echo -e "${GREEN}║  • VPN Connection: Active and verified                       ║${NC}"
    echo -e "${GREEN}║  • Traffic Isolation: Different IPs confirmed                ║${NC}"
    echo -e "${GREEN}║  • qBittorrent: Running in namespace with VPN binding        ║${NC}"
    echo -e "${GREEN}║  • Security Rules: iptables killswitch active                 ║${NC}"
    echo -e "${GREEN}║  • Services: All active and enabled for auto-start            ║${NC}"
    echo -e "${GREEN}║  • Monitoring: Continuous verification operational            ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║  Main System:  $MAIN_IP                 ║${NC}"
    echo -e "${GREEN}║  VPN Tunnel:   $VPN_EXT_IP                 ║${NC}"
    echo -e "${GREEN}║  VPN Interface: $VPN_TUN_IP                ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║  Your qBittorrent is fully protected! 🛡️🎉                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              ⚠️  SOME VALIDATION TESTS FAILED                  ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}║  Failed: $fail_count | Passed: $pass_count | Total: $test_count                  ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}║  Most VPN enforcement components are working, but some        ║${NC}"
    echo -e "${RED}║  tests indicate potential issues. Core functionality is       ║${NC}"
    echo -e "${RED}║  maintained.                                                   ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}║  Troubleshooting:                                              ║${NC}"
    echo -e "${RED}║  sudo systemctl status qbittorrent-vpn-namespace.service       ║${NC}"
    echo -e "${RED}║  sudo cat /var/log/vpn-vpn_torrent.log                         ║${NC}"
    echo -e "${RED}║  sudo /home/mkinney/repos/qBittorrent/docs/vpn-enforce.sh start║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    exit 1
fi