#!/bin/bash
# Auto-start VPN enforcement for qBittorrent
# Add this to cron or systemd for automatic startup

# Wait for network to be ready
sleep 10

# Start VPN enforcement
sudo /home/mkinney/repos/qBittorrent/docs/vpn-enforce.sh start

# Log status
echo "VPN Enforcement started: $(date)" >> /var/log/vpn-enforcement.log