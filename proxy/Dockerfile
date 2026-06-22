FROM ubuntu/squid:latest

# Install dnsmasq for DNS resolution
RUN apt-get update && apt-get install -y --no-install-recommends dnsmasq && \
    rm -rf /var/lib/apt/lists/*

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Custom entrypoint to start both dnsmasq and squid
ENTRYPOINT ["/entrypoint.sh"]
