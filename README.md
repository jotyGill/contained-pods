# Contained Pods

Podman containers with SSH access and network isolation via Squid proxy. Each container is fully isolated from the internet unless explicitly allowed through its proxy to reach specific hosts/domains. Core idea is to easily create isolated containers (for LLM agents/harnesses) that only have access to the specific hosts such as LLM API endpoints (optionally repos such as Ubuntu apt, python pip, npm etc) and nothing else. Data can be shared between a given container and the host via a shared folder, so you can view/edit/use files as needed. A ./config folder is setup to share configuration files with these containers for ease of config maintainability. The software inside the container runs as a non-root user. Sudo access is available using a custom password (for things like `apt install`). SSH is only exposed on the internal container network interface.

## Prerequisites

- **Podman** and **podman-compose** `sudo apt install podman podman-compose`
- Your chosen container password, exported as the `USER_PASSWORD` env var at build time. The password is set for the `appuser` account used for `sudo` or SSH.
- Optional SSH key pair (e.g. `~/.ssh/contained-dockers_rsa`)
---

## Setup

### 1. Setup SSH Authorized_keys and Password for the containers
```bash
# 1. Set the password for the container appuser account (use a real value)
export USER_PASSWORD='your_password_here'

# 2. Build the base image FIRST — variant pods (e.g. agents) depend on it
cd contained-dockers
podman-compose -f compose.yaml build

# 3. Create the shared external internet network (one-time)
podman network create internet-net

# 4. Build & run a variant
cd dockers/agents
podman-compose up -d

# 5. Drop into the container as appuser
podman exec -it --user appuser agents-contained zsh
```

### Step-by-step detail

**1. Set `USER_PASSWORD`**
This is consumed by the root `compose.yaml` build arg and baked into the base image as the `appuser` password. Keep it in your shell session (or a `.env` you source — do **not** commit it).

**2. Build the base image**
```bash
cd contained-dockers
podman-compose -f compose.yaml build
```
This builds `localhost/contained-pods:latest`. All variants (`dockers/<variant>/Dockerfile`) inherit `FROM localhost/contained-pods:latest`, so this **must** be built before any variant.

**3. Create `internet-net`** Only need to do this once
`internet-net` is referenced as an `external` network by every variant's proxy but is not defined inside a variant compose file, so it must exist on the host:
```bash
podman network create internet-net
```

**4. Build & run a new variant**
```bash
cd dockers/<variant-name>
podman-compose up -d
```
This builds the variant image and starts both `<variant>-contained` and `<variant>-contained-proxy`.

**5. Get a shell in the container**
```bash
podman exec -it --user appuser <variant>-contained zsh
```

Then configure the variant:
1. Edit `.env` with `VARIANT=llmagents`
2. Edit `Dockerfile` — install your software / dependencies
3. ⚠️ **MUST REVIEW** `proxy/squid.conf` — add the domains/IP and ports this variant needs to access

Example `.env` file:
```
VARIANT=llmagents
```
##TODO Example squidproxy section update

### 4. Build and run the variant

```bash
cd dockers/<variant-name>
podman-compose up -d
```


---

## Managing Variants

### Changing Proxy Restrictions
First edit the `<variant>/proxy/squid.conf` file to allow whatever access it needs, then restart the proxy container to apply the changes.
```bash
cd dockers/<variant-name>
podman-compose restart
```

### Starting / Stopping
To start/stop variant containers (container + proxy).

```bash
cd dockers/<variant-name>
podman-compose stop
# ... later
podman-compose up -d

## To Remove Completely
cd dockers/<variant-name>
podman-compose down
```
---


---

## Project Structure

```
contained-dockers/
├── Dockerfile          # Base image (SSH, tools, user setup)
├── compose.yaml        # Builds base image (needs USER_PASSWORD build arg)
├── set-proxy-dns.sh    # DNS-isolation entrypoint for the base image
├── config/             # Shared configs mounted to /home/appuser/config
│   └── ...             # Shell settings, aliases, env vars, etc.
├── proxy/              # Squid + dnsmasq proxy image
│   └── Dockerfile      # Squid proxy image (runs dnsmasq + squid)
└── dockers/
    ├── template-proxied/  # TEMPLATE: copy this to create a new variant
    │   ├── .env           # VARIANT=template-proxied
    │   ├── Dockerfile     # Variant dockerfile (FROM localhost/contained-pods:latest)
    │   ├── compose.yaml
    │   ├── proxy/
    │   │   ├── squid.conf # ⚠️ MUST REVIEW: Allowlist domains for this variant
    │   │   └── logs/      # Mounted proxy logs (git ignored)
    │   └── projects/      # Your code projects (git ignored)
    └── agents/            # Example variant: LLM coding agents
        ├── .env          # VARIANT=agents
        ├── Dockerfile
        ├── compose.yaml
        ├── proxy/
        │   ├── squid.conf
        │   └── logs/
        └── projects/
```

---

## Network Architecture

Each variant uses two networks to enforce isolation:

- **Internal network** (`internal: true`) — container can only reach its own squid proxy, not the internet
- **Internet network** (`external: true`) — only the squid proxy connects here to forward allowed traffic

Container → Proxy (allowed domains) → Internet

### Naming Conventions

| Component | Name | Example (agents) |
|-----------|------|-------------------------------|
| Container | `${VARIANT}-contained` | `agents-contained` |
| Proxy | `${VARIANT}-contained-proxy` | `agents-contained-proxy` |
| Internal net | `${VARIANT}-contained-net` | `agents-contained-net` |
| External net | `internet-net` | `internet-net` |
| Container image | `localhost/${VARIANT}-contained:latest` | `localhost/agents-contained:latest` |
| Proxy image | `localhost/${VARIANT}-contained-proxy:latest` | `localhost/agents-contained-proxy:latest` |

### IP Addressing

Each variant runs on its own `${VARIANT}-contained-net` subnet. IPs are assigned automatically by Podman To find a container's assigned IP:

```bash
podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${VARIANT}-contained
podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${VARIANT}-contained-proxy
```

(For reference, the old Docker-based scheme used fixed IPs `.5` for the container and `.50` for the proxy on a per-variant `NETWORK` subnet. Podman now assigns addresses automatically and the container locates its proxy by hostname via DNS isolation, see `set-proxy-dns.sh`.)

### DNS Containment

The proxy runs its own `dnsmasq` and squid's `squid.conf` is configured with `dns_nameservers 127.0.0.1`, so all DNS resolution for the pod is funneled through the proxy's allowlist. The container reaches the proxy via `${VARIANT}-contained-proxy:3128`.

### Diagram

```
┌──────────────────────────────────────────────────────────────────----─┐
│              ${VARIANT}-contained-net  (internal network)             │
│            Subnet: auto-assigned by Podman (no fixed IP)              │
│                                                                       │
│   ┌─────────────────────┐                  ┌──────────────────────┐   │
│   │     Container       │                  │        Proxy         │   │
│   │     (appuser)       │                  │        (root)        │   │
│   │                     │                  │                      │   │
│   │ ${VARIANT}-contained│   ───────────▶   │ ${VARIANT}-contained-│   │
│   │   IP via podman net │      port 3128   │      proxy           │   │
│   │                     │   ◀───────────   │   IP via podman net  │   │
│   └─────────────────────┘                  └───────────┬──────────┘   │
│                                                       │               │
└───────────────────────────────────────────────────────┼───────────────┘
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

To allow a domain (e.g. GitHub for code):
```
acl allowed dstdomain .github.com
```

If you need to change proxy rules, edit the `dockers/<variant>/proxy/squid.conf` for that container, then restart the proxy:
```bash
podman-compose -f dockers/<variant-name>/compose.yaml restart <variant>-contained-proxy
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `localhost/contained-pods:latest` not found | Run `podman-compose -f compose.yaml build` from project root first |
| Container can't reach domains | Check proxy is running: `podman ps \| grep squid` |
| Proxy config not taking effect | Edit `proxy/squid.conf` then `podman-compose -f dockers/<variant>/compose.yaml restart <variant>-contained-proxy` |
| Build fails / password not set | Ensure `USER_PASSWORD` is exported before building the base image |
| Variant won't start (network error) | Ensure `internet-net` exists: `podman network create internet-net` |

---

## Tips

- Each variant has its own `projects/` folder — mounts it at `/home/appuser/projects`
- The `.env` file defines `VARIANT` — change it per variant; the variant name drives the container, proxy, network, and image names
- The `config/` directory is shared across all variants and mounted at `/home/appuser/config` — put shell aliases, environment variables, or any container-wide configs here
