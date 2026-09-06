#!/bin/bash
set -euo pipefail

PROXY_NAME="${PROXY_NAME:-contained-proxy}"
PROXY_PORT="${PROXY_PORT:-3128}"
MAX_RETRIES=10
RETRY_DELAY=1

echo "Setting up DNS isolation via $PROXY_NAME..."

PROXY_IP=""
for i in $(seq 1 "$MAX_RETRIES"); do
    # `|| true` guards the assignment: with `set -e`, a failing `getent` (exit 2)
    # + pipefail would otherwise kill the script on attempt 1, making the retry
    # loop dead code. This is timing/host-dependent (works on some distros).
    PROXY_IP=$(getent hosts "$PROXY_NAME" 2>/dev/null | awk '{print $1}' | head -n1 || true)
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

# The proxy's DNS entry can appear before squid finishes starting; wait for it
# to actually accept connections, or fail closed.
proxy_up=0
for i in $(seq 1 "$MAX_RETRIES"); do
    if bash -c "exec 3<>/dev/tcp/${PROXY_IP}/${PROXY_PORT}" 2>/dev/null; then
        proxy_up=1
        break
    fi
    echo "Attempt $i/$MAX_RETRIES: proxy not yet listening on port ${PROXY_PORT}, retrying in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
done

if [ "$proxy_up" -ne 1 ]; then
    echo "ERROR: Proxy $PROXY_NAME ($PROXY_IP) not accepting connections on port ${PROXY_PORT} after $MAX_RETRIES attempts." >&2
    echo "Failing closed to prevent DNS leaks." >&2
    exit 1
fi

echo "nameserver $PROXY_IP" > /etc/resolv.conf
echo "DNS isolation configured: all queries go through $PROXY_NAME ($PROXY_IP)"

exec "$@"
