# Contained Dockers

Docker containers with SSH access and network isolation via Squid proxy. Each container is fully isolated from the internet unless explicitly allowed through its proxy to reach specific hosts/domains. Core idea is to easily create isolated docker containers (for LLM agents/harnesses) that only have access to the specific hosts such as LLM API endpoints (optionally repos such as Ubuntu apt, python pip, npm etc) and nothing else. Data can be shared between a given container and the host via a shared folder, so you can view/edit/use files as needed. A ./config folder is setup to share configuration files with these containers for ease of config maintainability. The software inside docker runs as non root user. Sudo access is available to you using a custom password if needed for things like apt install. ssh is only exposed on internal docker network interface.

## Prerequisites

- Docker & Docker Compose v2
- SSH key pair (e.g. `~/.ssh/contained-dockers_rsa`)
- A password file at `my_password.txt` in the project root

---

## Setup

### 1. Setup SSH Authorized_keys and Password for the containers
```bash
cd /home/jg/Nextcloud2/programming/dockers/contained-dockers
sudo docker compose build
```

### 1. Build the base image

```bash
cd /home/jg/Nextcloud2/programming/dockers/contained-dockers
sudo docker compose build
```

This builds `localhost/contained-dockers:latest` — all variants inherit from this.

### 2. Configure your variant

Each variant lives in `dockers/<variant-name>/`. Example for zed:

**Create `.env` file** (VARIANT + NETWORK unique per variant):
```bash
cd dockers/zed
```
Then create `.env`:
```
VARIANT=zed
NETWORK=10.88.1
```

### 3. Build & run the variant

```bash
cd dockers/<variant-name>
sudo docker compose up -d --build
```

### 4. SSH into the container

Each container gets a **hardcoded IP address** based on its `NETWORK` variable:
- Container: `${NETWORK}.5` (e.g., `10.88.1.5` for zed)
- Proxy: `${NETWORK}.50` (e.g., `10.88.1.50` for zed)

SSH commands:

```bash
# For zed (NETWORK=10.88.1)
ssh -i ~/.ssh/contained-dockers_rsa appuser@10.88.1.5

# For opencode (NETWORK=10.88.2)
ssh -i ~/.ssh/contained-dockers_rsa appuser@10.88.2.5
```

---

## Managing Variants

### Changing Proxy Restrictions
First edit the <variant> squid.conf file to allow whatever access it needs then restart the proxy container to apply the changes.
```bash
sudo docker restart <variant>-contained-proxy
```

### Starting / Stopping
To start/stop variant containers (container + proxy).

```bash
cd dockers/<variant-name>
sudo docker compose start/stop

## To Remove Completely
cd dockers/<variant-name>
sudo docker compose down
```
---

## Creating a New Variant

```bash
cp -r dockers/zed dockers/newapp
cd dockers/newapp
```

1. Create `.env` with `VARIANT=newapp` and unique `NETWORK=10.88.X`
2. Edit `Dockerfile` — install your app instead of Zed dependencies
3. ⚠️ **MUST REVIEW** `proxy/squid.conf` — add the domains this variant needs to access
4. Run: `sudo docker compose up -d --build`

---

## Project Structure

```
contained-dockers/
├── Dockerfile          # Base image (SSH, tools, user setup)
├── compose.yaml        # Build base image only
├── my_password.txt     # User password for sudo/SSH (secret)
├── config/             # Shared configs mounted to /home/appuser/config
│   └── ...             # Shell settings, aliases, env vars, etc.
├── proxy/              # Squid proxy basic config to build the proxy image
│   └── Dockerfile      # Squid proxy image
└── dockers/
    ├── zed/            # Variant: Zed Editor
    │   ├── .env        # VARIANT=zed, NETWORK=10.88.1
    │   ├── Dockerfile  # Variant dockerfile
    │   ├── compose.yaml
    │   ├── proxy/
    │   │   └── squid.conf  # ⚠️ MUST REVIEW: Allowlist domains for this variant
    │   └── projects/   # Your code projects (git ignored)
    ├── opencode/       # Variant: OpenCode CLI
    │   ├── .env        # VARIANT=opencode, NETWORK=10.88.2
    │   ├── Dockerfile  # Variant dockerfile
    │   ├── compose.yaml
    │   ├── proxy/
    │   │   └── squid.conf  # ⚠️ MUST REVIEW: Allowlist domains for this variant
    │   └── projects/   # Your code projects (git ignored)

```

---

## Network Architecture

Each variant uses two networks to enforce isolation:

- **Internal network** (`internal: true`) — container can only reach its own squid proxy, not the internet
- **Internet network** (`external: true`) — only the squid proxy connects here to forward allowed traffic

Container → Proxy (allowed domains) → Internet

### Naming Conventions

| Component | Name | Example (zed, NETWORK=10.88.1) |
|-----------|------|-------------------------------|
| Container | `${VARIANT}-contained` | `zed-contained` |
| Proxy | `${VARIANT}-contained-proxy` | `zed-contained-proxy` |
| Internal net | `${VARIANT}-contained-net` | `zed-contained-net` |
| External net | `internet-net` | `internet-net` |
| Container image | `localhost/${VARIANT}-contained:latest` | `localhost/zed-contained:latest` |
| Proxy image | `localhost/${VARIANT}-contained-proxy:latest` | `localhost/zed-contained-proxy:latest` |

### IP Addressing

Each network uses .5 for the actual container and .50 for the squid proxy. Example (zed, NETWORK=10.88.1) 

**IP Addressing:**
- Container IP: `${NETWORK}.5` (e.g., `10.88.1.5`)
- Proxy IP: `${NETWORK}.50` (e.g., `10.88.1.50`)
- Subnet: `${NETWORK}.0/24`

### Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     ${VARIANT}-contained-net (internal)         │
│ Subnet: ${NETWORK}.0/24                                         │
│                                                                 │
│   ┌──────────────────┐           ┌──────────────────────┐       │
│   │   Container      │           │   Proxy              │       │
│   │   (appuser)      │           │   (root)             │       │
│   │                  │           │                      │       │
│   │  ${NETWORK}.5    │◀────────▶ │   ${NETWORK}.50      │       │
│   │                  │   port    │                      │       │
│   └──────────────────┘   3128    └──────────┬───────────┘       │
│                                             │                   │
└─────────────────────────────────────────────┼───────────────────┘
                                              │
                                              │ (allowed domains only)
                                              ▼
                                    ┌──────────────────┐
                                    │   internet-net   │
                                    │   (external)     │
                                    └──────────────────┘
```


---

## How Proxies Work

Each variant has its own `proxy/squid.conf` that defines an **allowlist** of domains. By default, all traffic is blocked.

To allow a domain (e.g. GitHub for code):
```
acl allowed dstdomain .github.com
```

If you need to change proxy rules, edit the suid.conf for that container, then restart the proxy:
```bash
sudo docker compose restart <variant>-contained-proxy
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `localhost/contained-dockers:latest` not found | Run `sudo docker compose build` from project root first |
| Container can't reach domains | Check proxy is running: `docker ps \| grep squid` |
| Proxy config not taking effect | Edit `proxy/squid.conf` then `docker compose restart variant-contained-proxy` |
| Build fails with "secret" error | Ensure `my_password.txt` exists in project root |

---

## Tips

- Each variant has its own `projects/` folder — mounts it at `/home/appuser/projects`
- The `.env` file keeps VARIANT and NETWORK separated — must change them per variant
- The `config/` directory is shared across all variants and mounted at `/home/appuser/config` — put shell aliases, environment variables, or any container-wide configs here
