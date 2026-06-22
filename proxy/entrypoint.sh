#!/bin/bash
set -e

# Clean up stale PID file from previous run or squid -z
rm -f /run/squid.pid

# Start dnsmasq as DNS forwarder
# Use default system DNS servers as upstream
echo "Starting dnsmasq..."
dnsmasq --resolv-file=/etc/resolv.conf --no-daemon --port=53 --bind-interfaces &

sleep 1

echo "Initializing squid cache..."
/usr/sbin/squid -z 2>/dev/null || true

sleep 1

rm -f /run/squid.pid

echo "Starting squid..."
exec /usr/sbin/squid -N -f /etc/squid/squid.conf
