#!/bin/bash
set -e

# Detect interfaces by IP (names are non-deterministic in Podman)
INT_IP=$(ip -o -4 addr show | awk '{print $4}' | grep -vE '^169\.254|^127\.' | head -n1)
EXT_IP=$(ip -o -4 addr show | awk '{print $4}' | grep -vE '^169\.254|^127\.' | tail -n1)

if [ -n "$INT_IP" ]; then
    echo "Internal interface IP: $INT_IP"
fi
if [ -n "$EXT_IP" ]; then
    echo "External interface IP: $EXT_IP"
fi

# Clean up stale PID file from previous run or squid -z
rm -f /run/squid.pid

# 1. Ensure the log directory exists (important for containers)
mkdir -p /var/log/proxy-logs

# Start dnsmasq as DNS forwarder
# Use default system DNS servers as upstream
echo "Starting dnsmasq..."
##dnsmasq --resolv-file=/etc/resolv.conf --no-daemon --port=53 --bind-interfaces --listen-address=0.0.0.0 &
#dnsmasq --resolv-file=/etc/resolv.conf --no-daemon --port=53 --bind-interfaces --listen-address=0.0.0.0 --log-queries --log-facility=- &

# Start dnsmasq and redirect both stdout and stderr to the log file
dnsmasq --resolv-file=/etc/resolv.conf --no-daemon --port=53 --bind-interfaces --listen-address=0.0.0.0 --log-queries --log-facility=- >> /var/log/proxy-logs/dnsmasq.log 2>&1 &

sleep 1

# 2. Find out what user Squid runs as on your base image.
# (On Debian/Ubuntu it's 'proxy', on Alpine/CentOS it's usually 'squid')
SQUID_USER=$(grep -oP '^cache_effective_user \K.*' /etc/squid/squid.conf || echo "proxy")
SQUID_GROUP=$(grep -oP '^cache_effective_group \K.*' /etc/squid/squid.conf || echo "proxy")

# Fallback if the grep doesn't find it (common defaults)
if [ -z "$SQUID_USER" ] || [ "$SQUID_USER" = "root" ]; then
    SQUID_USER="proxy"
    SQUID_GROUP="proxy"
fi

# 3. Change ownership of the mounted volume to the Squid user
chown -R $SQUID_USER:$SQUID_GROUP /var/log/proxy-logs

# 4. Create the files and set permissions
touch /var/log/proxy-logs/squid-access.log
chown $SQUID_USER:$SQUID_GROUP /var/log/proxy-logs/squid-access.log
chmod 644 /var/log/proxy-logs/squid-access.log

echo "Initializing squid cache..."
/usr/sbin/squid -z 2>/dev/null || true

sleep 1

rm -f /run/squid.pid

echo "Starting squid..."
exec /usr/sbin/squid -N -f /etc/squid/squid.conf
