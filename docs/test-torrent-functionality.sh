#!/bin/bash
# Comprehensive VPN enforcement and torrent functionality test

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

# Test counter
tests_passed=0
tests_failed=0

run_test() {
    local test_name="$1"
    local test_command="$2"

    log_info "Running: $test_name"
    if eval "$test_command" &>/dev/null; then
        log_success "$test_name"
        ((tests_passed++))
        return 0
    else
        log_error "$test_name"
        ((tests_failed++))
        return 1
    fi
}

echo "=================================="
echo "  VPN Enforcement Test Suite"
echo "=================================="
echo ""

# Section 1: Infrastructure Tests
log "Section 1: Infrastructure Tests"
echo ""

run_test "Network namespace exists" "sudo ip netns list | grep -q vpn_torrent"
run_test "VPN tunnel interface exists" "sudo ip netns exec vpn_torrent ip addr show tun0 | grep -q 'inet '"
run_test "qBittorrent process running" "sudo systemctl is-active qbittorrent-vpn.service"
run_test "VPN monitoring service running" "sudo systemctl is-active vpn-monitor.service"

echo ""

# Section 2: VPN Connectivity Tests
log "Section 2: VPN Connectivity Tests"
echo ""

# Get IPs for comparison
MAIN_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Failed")
VPN_IP=$(sudo ip netns exec vpn_torrent timeout 5 curl -s ifconfig.me 2>/dev/null || echo "Failed")

log_info "Main System IP: $MAIN_IP"
log_info "VPN Tunnel IP:  $VPN_IP"

if [[ "$VPN_IP" != "Failed" ]] && [[ "$MAIN_IP" != "Failed" ]] && [[ "$VPN_IP" != "$MAIN_IP" ]]; then
    log_success "Traffic isolation verified (different IPs)"
    ((tests_passed++))
else
    log_error "Traffic isolation failed or connectivity issues"
    ((tests_failed++))
fi

run_test "VPN interface has IP address" "sudo ip netns exec vpn_torrent ip addr show tun0 | grep -q 'inet '"
run_test "qBittorrent listening in namespace" "sudo ip netns exec vpn_torrent netstat -tlnp | grep -q 6881"

echo ""

# Section 3: qBittorrent Configuration Tests
log "Section 3: qBittorrent Configuration Tests"
echo ""

run_test "qBittorrent WebUI accessible (HTTP)" "sudo ip netns exec vpn_torrent curl -s http://localhost:8080 | grep -q qBittorrent"
run_test "qBittorrent config directory exists" "test -d /var/lib/qbittorrent"
run_test "Download directories exist" "test -d /nas/Downloads/Complete && test -d /nas/Downloads/Incomplete"

echo ""

# Section 4: Security Tests
log "Section 4: Security Tests"
echo ""

# Check iptables rules
if sudo ip netns exec vpn_torrent iptables -L OUTPUT | grep -q "tun0.*ACCEPT"; then
    log_success "VPN traffic allowed through tunnel interface"
    ((tests_passed++))
else
    log_error "VPN traffic NOT allowed through tunnel interface"
    ((tests_failed++))
fi

# Check P2P port blocking
if sudo ip netns exec vpn_torrent iptables -L OUTPUT | grep -q "6881.*REJECT"; then
    log_success "P2P ports blocked on non-VPN interface"
    ((tests_passed++))
else
    log_warning "P2P ports may not be blocked on non-VPN interface"
    ((tests_failed++))
fi

# Check that qBittorrent can only bind to VPN interface
if sudo ip netns exec vpn_torrent netstat -tlnp | grep "10.16.0" | grep -q "6881"; then
    log_success "qBittorrent bound to VPN interface"
    ((tests_passed++))
else
    log_warning "qBittorrent may not be bound to VPN interface"
    ((tests_failed++))
fi

echo ""

# Section 5: Service Integration Tests
log "Section 5: Service Integration Tests"
echo ""

run_test "VPN namespace service enabled" "sudo systemctl is-enabled qbittorrent-vpn-namespace.service"
run_test "qBittorrent service enabled" "sudo systemctl is-enabled qbittorrent-vpn.service"
run_test "VPN monitor service enabled" "sudo systemctl is-enabled vpn-monitor.service"

echo ""

# Final Summary
echo "=================================="
echo "  Test Summary"
echo "=================================="
echo ""
echo -e "${GREEN}Tests Passed: $tests_passed${NC}"
echo -e "${RED}Tests Failed: $tests_failed${NC}"
echo ""

if [[ $tests_failed -eq 0 ]]; then
    echo -e "${GREEN}🎉 All tests passed! VPN enforcement is working correctly.${NC}"
    echo ""
    echo "Your qBittorrent installation is properly secured with:"
    echo "  ✅ VPN-only traffic enforcement"
    echo "  ✅ Network namespace isolation"
    echo "  ✅ P2P port blocking on non-VPN interface"
    echo "  ✅ Continuous VPN monitoring"
    echo "  ✅ Auto-start on boot"
    echo ""
    echo "You can safely use qBittorrent for torrenting!"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Please review the issues above.${NC}"
    echo ""
    echo "Troubleshooting tips:"
    echo "  • Check VPN logs: sudo cat /var/log/vpn-vpn_torrent.log"
    echo "  • Check service status: sudo systemctl status qbittorrent-vpn-namespace.service"
    echo "  • Restart enforcement: sudo /home/mkinney/repos/qBittorrent/docs/vpn-enforce.sh start"
    exit 1
fi