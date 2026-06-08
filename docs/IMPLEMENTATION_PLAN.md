# qBittorrent VPN Enforcement Implementation Plan

## Current Issues
1. Namespace VPN authentication failing (AUTH_FAILED)
2. No tun0 interface in namespace
3. Traffic leaking through system-wide VPN instead of isolated tunnel
4. No killswitch protection

## Security Requirements
1. VPN killswitch - block all non-VPN traffic
2. Namespace isolation - enforce VPN-only routing
3. Authentication fixes
4. Monitoring and auto-recovery

## Implementation Tasks
1. Fix VPN credentials/configuration
2. Add iptables killswitch rules
3. Create VPN monitoring service
4. Add interface binding enforcement
5. Testing and validation