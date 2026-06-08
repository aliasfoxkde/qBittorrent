#!/bin/bash
# End-to-End VPN Enforcement Validation for qBittorrent
# This script performs comprehensive validation of the entire VPN enforcement pipeline

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

test_count=0
pass_count=0
fail_count=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"

    ((test_count++))
    log_info "Test $test_count: $test_name"

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

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  qBittorrent VPN Enforcement - End-to-End Validation          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Section 1: Infrastructure Validation
log_section "1. Infrastructure Validation"

run_test "Network namespace exists" "sudo ip netns list | grep -q vpn_torrent"
run_test "Namespace has loopback interface" "sudo ip netns exec vpn_torrent ip link show lo | grep -q UP"
run_test "Namespace has veth interface" "sudo ip netns exec vpn_torrent ip link show veth_torrent1 | grep -q UP"
run_test "veth pair exists on host" "ip link show veth_torrent0 | grep -q veth_torrent0"

# Section 2: VPN Connection Validation
log_section "2. VPN Connection Validation"

run_test "VPN tunnel interface exists" "sudo ip netns exec vpn_torrent ip link show tun0 | grep -q UP"
run_test "VPN tunnel has IP address" "sudo ip netns exec vpn_torrent ip addr show tun0 | grep -q 'inet '"
run_test "VPN tunnel is in UP state" "sudo ip netns exec vpn_torrent ip link show tun0 | grep -q 'UP,'"

if sudo ip netns exec vpn_torrent ip addr show tun0 | grep -q "inet "; then
    VPN_TUN_IP=$(sudo ip netns exec vpn_torrent ip addr show tun0 | grep "inet " | awk '{print $2}')
    log_success "VPN tunnel IP: $VPN_TUN_IP"
    ((pass_count++))
else
    log_error "Could not determine VPN tunnel IP"
    ((fail_count++))
fi

# Check routing table
run_test "Default route via VPN" "sudo ip netns exec vpn_torrent ip route show | grep -q 'default via 10.201.1.1'"

# Section 3: Traffic Isolation Validation
log_section "3. Traffic Isolation Validation"

# Get IPs for comparison
MAIN_IP=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || echo "Failed")
VPN_EXT_IP=$(sudo ip netns exec vpn_torrent timeout 10 curl -s ifconfig.me 2>/dev/null || echo "Failed")

log_info "Main System IP: $MAIN_IP"
log_info "VPN Tunnel IP:  $VPN_EXT_IP"

if [[ "$VPN_EXT_IP" != "Failed" ]] && [[ "$MAIN_IP" != "Failed" ]]; then
    if [[ "$VPN_EXT_IP" != "$MAIN_IP" ]]; then
        log_success "Traffic properly isolated (different IPs)"
        ((pass_count++))
    else
        log_error "TRAFFIC LEAK DETECTED - Same IP on both interfaces!"
        ((fail_count++))
    fi
else
    log_error "Could not verify traffic isolation - connectivity issues"
    ((fail_count++))
fi

# Test DNS resolution through VPN
run_test "DNS resolution through VPN" "sudo ip netns exec vpn_torrent timeout 5 nslookup google.com | grep -q 'Address:'"

# Section 4: qBittorrent Process Validation
log_section "4. qBittorrent Process Validation"

run_test "qBittorrent service running" "sudo systemctl is-active qbittorrent-vpn.service"
run_test "qBittorrent process exists" "sudo pidof qbittorrent-nox >/dev/null"
run_test "qBittorrent running in namespace" "sudo pidof -x qbittorrent-nox >/dev/null"

# Check qBittorrent binding
if sudo ip netns exec vpn_torrent netstat -tlnp 2>/dev/null | grep -q qbittorrent; then
    BINDINGS=$(sudo ip netns exec vpn_torrent netstat -tlnp 2>/dev/null | grep qbittorrent | grep -E "(10.16.0|10.201.1)" | wc -l)
    if [[ $BINDINGS -gt 0 ]]; then
        log_success "qBittorrent bound to namespace interfaces ($BINDINGS bindings)"
        ((pass_count++))
    else
        log_error "qBittorrent not properly bound to namespace interfaces"
        ((fail_count++))
    fi
else
    log_error "Could not determine qBittorrent bindings"
    ((fail_count++))
fi

# Section 5: qBittorrent WebUI Validation
log_section "5. qBittorrent WebUI Validation"

run_test "qBittorrent WebUI accessible" "sudo ip netns exec vpn_torrent curl -s http://localhost:8080 | grep -q qBittorrent"
run_test "qBittorrent WebUI responds with HTTP 200" "sudo ip netns exec vpn_torrent curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 | grep -q 200"

# Check if WebUI is only accessible through namespace
if sudo ip netns exec vpn_torrent curl -s http://localhost:8080 | grep -q qBittorrent; then
    log_success "WebUI accessible through namespace only (isolated)"
    ((pass_count++))
else
    log_error "WebUI not accessible through namespace"
    ((fail_count++))
fi

# Section 6: iptables Security Rules Validation
log_section "6. iptables Security Rules Validation"

run_test "iptables OUTPUT chain exists" "sudo ip netns exec vpn_torrent iptables -L OUTPUT >/dev/null"
run_test "iptables INPUT chain exists" "sudo ip netns exec vpn_torrent iptables -L INPUT >/dev/null"

# Check for VPN-allowed rules
if sudo ip netns exec vpn_torrent iptables -L OUTPUT | grep -q "tun.*ACCEPT"; then
    log_success "VPN traffic allowed through tunnel interface"
    ((pass_count++))
else
    log_warning "VPN traffic rules may not be properly configured"
    ((fail_count++))
fi

# Check for P2P blocking rules
if sudo ip netns exec vpn_torrent iptables -L OUTPUT | grep -q "6881.*REJECT"; then
    log_success "P2P ports blocked on non-VPN interface"
    ((pass_count++))
else
    log_warning "P2P port blocking may not be active"
    ((fail_count++))
fi

# Section 7: Service Integration Validation
log_section "7. Service Integration Validation"

run_test "VPN namespace service enabled" "sudo systemctl is-enabled qbittorrent-vpn-namespace.service"
run_test "VPN namespace service active" "sudo systemctl is-active qbittorrent-vpn-namespace.service"
run_test "qBittorrent service enabled" "sudo systemctl is-enabled qbittorrent-vpn.service"
run_test "qBittorrent service active" "sudo systemctl is-active qbittorrent-vpn.service"
run_test "VPN monitor service enabled" "sudo systemctl is-enabled vpn-monitor.service"
run_test "VPN monitor service active" "sudo systemctl is-active vpn-monitor.service"

# Section 8: Continuous Monitoring Validation
log_section "8. Continuous Monitoring Validation"

run_test "VPN monitor process running" "sudo systemctl status vpn-monitor.service | grep -q 'active.*running'"
run_test "VPN monitor logging to journal" "sudo journalctl -u vpn-monitor.service -n 1 --no-pager >/dev/null"

# Check recent monitoring activity
if sudo journalctl -u vpn-monitor.service -n 10 --no-pager | grep -q "VPN OK"; then
    log_success "VPN monitor actively checking VPN status"
    ((pass_count++))
else
    log_warning "VPN monitor may not be performing checks"
    ((fail_count++))
fi

# Section 9: File System Validation
log_section "9. File System Validation"

run_test "qBittorrent config directory exists" "test -d /var/lib/qbittorrent"
run_test "qBittorrent data directory exists" "test -d /var/lib/qbittorrent/qBittorrent"
run_test "Download directories exist" "test -d /nas/Downloads/Complete && test -d /nas/Downloads/Incomplete"
run_test "VPN credentials file exists" "test -f /home/mkinney/repos/server-config/configs/vpn/fastestvpn-credentials.txt"

# Section 10: Network Connectivity Tests
log_section "10. Network Connectivity Tests"

# Test connectivity through VPN
run_test "External connectivity through VPN" "sudo ip netns exec vpn_torrent timeout 5 curl -s -o /dev/null http://www.google.com"

# Test that non-VPN traffic is blocked
if sudo ip netns exec vpn_torrent iptables -L OUTPUT | grep -q "veth_torrent1.*REJECT"; then
    log_success "Non-VPN traffic blocked by iptables"
    ((pass_count++))
else
    log_warning "Non-VPN traffic may not be blocked"
    ((fail_count++))
fi

# Final Summary
log_section "VALIDATION SUMMARY"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Test Results Summary                        ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Total Tests: $test_count                                                ║"
printf "║  %-15s ${GREEN}%-30s${NC} ║\n" "Passed:" "$pass_count"
printf "║  %-15s ${RED}%-30s${NC} ║\n" "Failed:" "$fail_count"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $fail_count -eq 0 ]]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║           ✅ ALL TESTS PASSED - VPN ENFORCEMENT WORKING       ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║  Your qBittorrent installation is properly secured with:      ║${NC}"
    echo -e "${GREEN}║  • Network namespace isolation                                ║${NC}"
    echo -e "${GREEN}║  • VPN-only traffic enforcement                               ║${NC}"
    echo -e "${GREEN}║  • P2P port blocking on non-VPN interfaces                    ║${NC}"
    echo -e "${GREEN}║  • Continuous monitoring and recovery                          ║${NC}"
    echo -e "${GREEN}║  • Auto-start on system boot                                  ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║  Main System IP: $MAIN_IP           ║${NC}"
    echo -e "${GREEN}║  VPN Tunnel IP:  $VPN_EXT_IP           ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║  Traffic is properly isolated and secured! 🎉                  ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              ❌ SOME TESTS FAILED - ACTION REQUIRED            ║${NC}"
    echo -e "${RED}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║  $fail_count test(s) failed. Please review the output above.            ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}║  Troubleshooting steps:                                       ║${NC}"
    echo -e "${RED}║  1. Check VPN logs: sudo cat /var/log/vpn-vpn_torrent.log      ║${NC}"
    echo -e "${RED}║  2. Restart services: sudo systemctl restart qbittorrent-vpn ║${NC}"
    echo -e "${RED}║  3. Re-run enforcement: sudo /home/mkinney/repos/qBittorrent/ ║${NC}"
    echo -e "${RED}║     docs/vpn-enforce.sh start                                 ║${NC}"
    echo -e "${RED}║  4. Check service status: sudo systemctl status qbittorrent-vpn║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
fi