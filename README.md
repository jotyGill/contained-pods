# Contained Pods

Podman containers (pods) with network isolation and traffic logging.

# Why
- A simple project to run LLM/coding agents in isolated environments with control and visibility using stable tech (Podman and Squid).
- Podman runs rootless (unlike default Docker): no privileged daemon, and in-container root maps to an unprivileged host UID.
- All traffic, including DNS, is forced through a separate Squid proxy container. Even if an agent gains root, it cannot reroute traffic.
- Default-deny: you explicitly allow only the specific domains / subdomains / IP / port combinations each container/pod can reach.
- Request logging and dashboard for easy analysis, see exactly what your agents are trying to reach (check out logviewer.py).
- The inner `poduser` has `sudo` (e.g. for `apt install`) but requires a password you set at build time.
- Easy host↔container file sharing: each container gets a mounted `~/projects/` directory.
- Easy management of your configurations, dotfiles and scripts; a shared `~/config/` directory for unified setups.

## Prerequisites

- **Podman** and **podman-compose**: `sudo apt install podman podman-compose`
- Your chosen container password, exported as the `PODUSER_PASSWORD` env var at build time. The password is set for the `poduser` account used for `sudo`.

---

## Pod Setup Guide

How to create and run an isolated container/pod varient.

### Overview

1. Set the `PODUSER_PASSWORD` environment variable
2. Build the base image (`localhost/contained-pods:latest`)
3. Create the shared `internet-net` network (one-time)
4. Create a new variant (or use the existing `agents`)
5. Configure the variant's `.env` file
6. Review and customize the proxy allowlist (`proxy/squid.conf`)
7. Build and start the variant
8. Verify the container is running
9. Access the container

---

### 1. Set the Container Password

The `PODUSER_PASSWORD` environment variable is used during the base image build to set the password for the `poduser` account. This password is also used for `sudo` access.
```bash
# Set the password for your containers 'poduser'
export PODUSER_PASSWORD='your_password_here'
```

---

### 2. Build the Base Image

The base image (`localhost/contained-pods:latest`) must be built first, as all variant Dockerfiles inherit from it. Run this from the project root (the `contained-dockers` directory):
```bash
podman-compose -f compose.yaml build
```

---

### 3. Create the Internet Network (One-Time Setup)

The `internet-net` network is an external network that allows the proxy containers to reach the internet.
```bash
# Only needs to be done once
podman network create internet-net
```

---

### 4. Create or Choose a Variant

#### Option A: Use an Existing Variant

If you want to use a pre-existing variant `agents`, its `VARIANT`, skip to [Step 6](#6-review-and-customize-the-proxy-allowlist) and review/customize its `proxy/squid.conf` as needed.

```bash
# List available variants
ls dockers/
```

#### Option B: Create a New Variant from Template

To create a new isolated container, copy the `template-proxied` directory and customize it:

```bash
# Copy the template
cp -r dockers/template-proxied dockers/myvariant
```

The copy becomes your new variant. Continue to [Step 5](#5-configure-the-variant-env-file) and [Step 6](#6-review-and-customize-the-proxy-allowlist) to configure it.

---

### 5. Configure the Variant (`.env` file)

Set your `VARIANT` name in the variant's `.env` file:

```bash
cd dockers/<variant-name>
nano .env
```

```env
VARIANT=myvariant
```

The `VARIANT` value determines:
- Container name: `${VARIANT}-contained`
- Proxy name: `${VARIANT}-contained-proxy`
- Network name: `${VARIANT}-contained-net`
- Image names: `localhost/${VARIANT}-contained:latest` and `localhost/${VARIANT}-contained-proxy:latest`

Optionally edit the variant's `Dockerfile` to add your own software/dependencies.

---

### 6. Review and Customize the Proxy Allowlist (`proxy/squid.conf`)

**REQUIRED**: Define which domains/IPs this variant can access. By default, all outbound traffic is blocked.

```bash
cd dockers/<variant-name>
nano proxy/squid.conf
```

Example allowlist:
```conf
# Allow access to GitHub
acl allowed dstdomain .github.com
http_access allow allowed

# Allow access to PyPI
acl allowed dstdomain .pypi.org
acl allowed dstdomain .pythonhosted.org
http_access allow allowed

# Deny everything else
http_access deny all
```

---

### 7. Build and Start the Variant

Build the variant image and start both the container and its proxy:

```bash
cd dockers/<variant-name>
podman-compose up -d --build
```

---

### 8. Verify Everything is Running

Check that both containers are up and running:

```bash
# List all running containers
podman ps -a

# You should see both:
# - <variant>-contained
# - <variant>-contained-proxy
```

If the container can't reach allowed domains, check:
1. Is the proxy running? (`podman ps | grep proxy`)
2. Does `squid.conf` have the correct allowlist entries?
3. Was the proxy restarted after editing `squid.conf`?

---

### 9. Access the Container

Access the container directly using `podman exec` (no SSH needed):

```bash
podman exec -it --user poduser <variant>-contained zsh
```

Once inside, you can:
- Access your projects at `/home/poduser/projects`
- Use shared configs at `/home/poduser/config`
- Use `sudo` with the password you set in Step 1
- Install packages (in the template config apt sources are allowed (nothing else is allowed by default))

---

## Managing Variants

### Changing Proxy Rules

After editing `proxy/squid.conf`, restart those pods to apply changes:

```bash
cd dockers/<variant-name>
podman-compose restart
```

### Starting / Stopping

```bash
cd dockers/<variant-name>

# Stop containers (preserves data)
podman-compose stop

# Start again
podman-compose start

# Stop and remove containers (preserves images and volumes)
podman-compose down
```

### Rebuilding After Changes

If you modify the variant's `Dockerfile`:

```bash
# Rebuild variant
cd dockers/<variant-name>
podman-compose up -d --build
```

---

## Project Structure

```
contained-dockers/
├── Dockerfile                 # Base image (SSH, tools, user setup)
├── compose.yaml               # Builds base image (needs PODUSER_PASSWORD build arg)
├── logserver.py              # Optional helper: serves logviewer + auto-discovers
├── set-proxy-dns.sh           # DNS-isolation entrypoint for the base image
├── config/                    # Shared configs mounted to /home/poduser/config
│   └── ...                    # Shell settings, aliases, env vars, etc.
├── proxy/
│   └── Dockerfile             # Squid proxy image (runs dnsmasq + squid)
└── dockers/
    ├── template-proxied/      # TEMPLATE: copy this to create a new variant
    │   ├── .env               # VARIANT=template-proxied
    │   ├── Dockerfile         # Variant dockerfile (FROM localhost/contained-pods:latest)
    │   ├── compose.yaml
    │   ├── proxy/
    │   │   ├── squid.conf     # ⚠️ MUST REVIEW: Allowlist domains for this variant
    │   │   └── logs/          # Mounted proxy logs (git ignored)
    │   └── projects/          # Your code projects (git ignored)
    ├── agents/                # Example variant: LLM coding agents
    │   ├── .env               # VARIANT=agents
    │   ├── Dockerfile
    │   ├── compose.yaml
    │   ├── proxy/
    │   │   ├── squid.conf
    │   │   └── logs/
    │   └── projects/
    └── ...                    # Other variants
```

---

## Network Architecture

Each variant uses two networks to enforce isolation:

- **Internal network** (`internal: true`) — container can only reach its own squid proxy, not the internet directly
- **Internet network** (`external: true`) — only the squid proxy connects here to forward allowed traffic

Container → Proxy (allowed domains/IPs/ports only) → Internet

### Naming Conventions

| Component | Name Pattern | Example (agents) |
|-----------|--------------|------------------|
| Container | `${VARIANT}-contained` | `agents-contained` |
| Proxy | `${VARIANT}-contained-proxy` | `agents-contained-proxy` |
| Internal net | `${VARIANT}-contained-net` | `agents-contained-net` |
| External net | `internet-net` | `internet-net` |
| Container image | `localhost/${VARIANT}-contained:latest` | `localhost/agents-contained:latest` |
| Proxy image | `localhost/${VARIANT}-contained-proxy:latest` | `localhost/agents-contained-proxy:latest` |

### IP Addressing

Each variant runs on its own `${VARIANT}-contained-net` subnet. IPs are assigned automatically by Podman. The container locates its proxy by hostname via DNS isolation (see `set-proxy-dns.sh`).


### DNS Containment

The proxy runs its own `dnsmasq` and squid's `squid.conf` is configured with `dns_nameservers 127.0.0.1`, so all DNS resolution for the pod is funneled through the proxy's allowlist. The container reaches the proxy via `${VARIANT}-contained-proxy:3128`.

### Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│           ${VARIANT}-contained-net  (internal network)                  │
│         Subnet: auto-assigned by Podman (no fixed IP)                   │
│                                                                         │
│   ┌──────────────────────┐               ┌────────────────────────┐     │
│   │     Container        │               │        Proxy           │     │
│   │     (poduser)        │               │        (root)          │     │
│   │                      │               │                        │     │
│   │ ${VARIANT}-contained │  ──────────▶  │ ${VARIANT}-contained-  │     │
│   │                      │   port 3128   │      proxy             │     │
│   │                      │  ◀──────────  │          │             │
│   └──────────────────────┘               └──────────┬─────────────┘     │
│                                                     │                   │
└─────────────────────────────────────────────────────┼───────────────────┘
                                                      │
                                                      │ (allowed domains/IPs/ports only)
                                                      ▼
                                          ┌──────────────────────┐
                                          │     internet-net     │
                                          │     (external)       │
                                          └──────────────────────┘
```

---

## How Proxies Work

Each variant has its own `proxy/squid.conf` that defines an **allowlist** of domains. By default, all traffic is blocked.

To allow a domain (e.g., GitHub for code):
```conf
acl allowed dstdomain .github.com
http_access allow allowed
```

If you need to change proxy rules, edit the `dockers/<variant>/proxy/squid.conf` for that container, then restart the proxy:

```bash
podman restart <variant>-contained-proxy

# Might need to restart its main pod too
podman restart <variant>-contained
```

---

## Squid Log Viewer

`logviewer` is a setup to view the traffic requests from your pods using the Squid access logs. It shows Squid access logs requests, what requests are being sent, what is being blocked. Actually see what requests your tools/agents are attempting. Run the tiny `logserver.py` helper:

```bash
cd contained-dockers
sudo python3 logserver.py --port 8090
```

Then open http://127.0.0.1:8090/ it auto-discovers every container's `proxy/logs/squid-access.log`.

Why not open `logviewer.html` directly? proxy pods write logs owned using a different UID, so the browsers couldn't read them even with world read permissions. (Belive me I tried different apporaches but this setup needs: rootless podman + running DNS server on proxy port 53 to monitor traffic). Run this helper as root using sudo.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `localhost/contained-pods:latest` not found | Run `podman-compose -f compose.yaml build` from project root first |
| Container can't reach allowed domains | Check proxy is running: `podman ps \| grep proxy` |
| Proxy config changes not taking effect | Edit `proxy/squid.conf` then `podman restart <variant>-contained-proxy` then `podman restart <variant>-contained`|
| Build fails / password not set | Ensure `PODUSER_PASSWORD` is exported before building the base image |
| Variant won't start (network error) | Ensure `internet-net` exists: `podman network create internet-net` |
| `podman exec` access denied | Ensure `PODUSER_PASSWORD` was set correctly during base image build |

---

## Tips

- Each variant has its own `projects/` folder — it's mounted at `/home/poduser/projects` inside the container
- The `.env` file defines `VARIANT` — change it per variant; the variant name drives the container, proxy, network, and image names
- The `config/` directory is shared across all variants and mounted at `/home/poduser/config` — put shell aliases, environment variables, or any container-wide configs here
- Use `podman-compose logs -f` to follow container logs in real-time
- The proxy logs are available at `dockers/<variant>/proxy/logs/` on the host

---

## License

This project is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html) (GPLv3).
