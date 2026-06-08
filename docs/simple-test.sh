#!/bin/bash
# Simple VPN enforcement verification

echo "=== VPN Enforcement Verification ==="
echo ""

# Test 1: Namespace exists
if sudo ip netns list | grep -q vpn_torrent; then
    echo "✓ Network namespace exists"
else
    echo "✗ Network namespace NOT found"
    exit 1
fi

# Test 2: VPN interface up
if sudo ip netns exec vpn_torrent ip addr show tun0 | grep -q "inet "; then
    VPN_IP=$(sudo ip netns exec vpn_torrent ip addr show tun0 | grep "inet " | awk '{print $2}')
    echo "✓ VPN interface up: $VPN_IP"
else
    echo "✗ VPN interface NOT up"
    exit 1
fi

# Test 3: Traffic isolation
MAIN_IP=$(curl -s --max-time 5 ifconfig.me)
VPN_EXT_IP=$(sudo ip netns exec vpn_torrent timeout 5 curl -s ifconfig.me)

if [[ "$VPN_EXT_IP" != "$MAIN_IP" ]] && [[ "$VPN_EXT_IP" != "Failed" ]]; then
    echo "✓ Traffic isolated:"
    echo "  Main: $MAIN_IP"
    echo "  VPN:  $VPN_EXT_IP"
else
    echo "✗ Traffic NOT properly isolated"
    exit 1
fi

# Test 4: qBittorrent running
if sudo systemctl is-active --quiet qbittorrent-vpn.service; then
    echo "✓ qBittorrent service running"
else
    echo "✗ qBittorrent service NOT running"
    exit 1
fi

# Test 5: qBittorrent accessible
if sudo ip netns exec vpn_torrent curl -s http://localhost:8080 | grep -q "qBittorrent"; then
    echo "✓ qBittorrent WebUI accessible"
else
    echo "✗ qBittorrent WebUI NOT accessible"
    exit 1
fi

# Test 6: qBittorrent bound to VPN
if sudo ip netns exec vpn_torrent netstat -tlnp | grep "10.16.0" | grep -q "6881"; then
    echo "✓ qBittorrent bound to VPN interface"
else
    echo "✗ qBittorrent NOT bound to VPN interface"
    exit 1
fi

echo ""
echo "=== ✅ All Tests Passed ==="
echo ""
echo "VPN enforcement is working correctly!"
echo "Your qBittorrent is safely isolated and protected."