# VPN Enforcement Solution

## Current Status
✅ **VPN Working**: Tunnel established at 10.16.0.41, external IP: 23.95.75.25
✅ **qBittorrent Running**: Service active in namespace
❌ **Killswitch Issues**: Blocking legitimate VPN traffic

## Security Implementation Plan

### Option 1: Simple Interface-Based Killswitch
```bash
# Allow ONLY traffic through VPN interface (tun+)
# Block everything through veth (non-VPN)
# Allow DNS/VPN setup traffic during connection
```

### Option 2: VPN Monitoring + Auto-Shutdown
```bash
# Monitor VPN interface status
# If VPN goes down, immediately stop qBittorrent
# More practical than complex iptables rules
```

### Option 3: Network Namespace Isolation (Current)
```bash
# qBittorrent already runs in isolated namespace
# Just need proper VPN enforcement
# Killswitch should be applied AFTER VPN is established
```

## Recommended Solution: Hybrid Approach
1. **Start VPN first** (without killswitch)
2. **Wait for VPN to establish** (check tun0 interface)
3. **Apply killswitch rules** (blocking non-VPN traffic)
4. **Monitor VPN status** (restart qBittorrent if VPN fails)

## Testing Commands
```bash
# Check VPN status
sudo ip netns exec vpn_torrent ip addr show tun0

# Check external IP
sudo ip netns exec vpn_torrent curl -s ifconfig.me

# Check qBittorrent
sudo systemctl status qbittorrent-vpn.service
```