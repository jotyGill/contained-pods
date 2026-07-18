#!/bin/bash
set -euo pipefail

PROXY_NAME="${PROXY_NAME:-contained-proxy}"
MAX_RETRIES=10
RETRY_DELAY=1

echo "Setting up DNS isolation via $PROXY_NAME..."

PROXY_IP=""
for i in $(seq 1 "$MAX_RETRIES"); do
    PROXY_IP=$(getent hosts "$PROXY_NAME" | awk '{print $1}' | head -n1)
    if [ -n "$PROXY_IP" ]; then
        echo "Resolved $PROXY_NAME to $PROXY_IP"
        break
    fi
    echo "Attempt $i/$MAX_RETRIES: $PROXY_NAME not yet resolvable, retrying in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
done

if [ -z "$PROXY_IP" ]; then
    echo "ERROR: Cannot resolve $PROXY_NAME after $MAX_RETRIES attempts." >&2
    echo "Failing closed to prevent DNS leaks." >&2
    exit 1
fi

echo "nameserver $PROXY_IP" > /etc/resolv.conf
echo "DNS isolation configured: all queries go through $PROXY_NAME ($PROXY_IP)"

exec "$@"
