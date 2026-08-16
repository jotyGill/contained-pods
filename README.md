# Contained Pods

Spinup Podman containers with network isolation and traffic logging to run coding/LLM agents, untrusted tools, anything really.

## Why
- A simple project to run LLM/coding agents in isolated environments with control and visibility using stable tech (Podman and Squid).
- Podman runs rootless (unlike default Docker): no privileged daemon, and in-container root maps to an unprivileged host UID.
- All traffic, including DNS, is forced through a separate Squid proxy container. Even if an agent gains root, it cannot reroute traffic.
- Default-deny: you explicitly allow only the specific domains / subdomains / IP / port combinations each container/pod can reach.
- Traffic logging and dashboard for easy analysis, see exactly what your agents are trying to reach (check out logserver.py).
- The inner `poduser` has `sudo` (e.g. for `apt install`) but requires a password you set at build time.
- Easy host↔container file sharing: each container gets a mounted `~/projects/` directory.
- Easy management of your configurations, dotfiles and scripts; a shared `~/config/` directory for unified setups. Mounted as read only to prevent cross-pod lateral movement. You can change it to write access for convenience if you don't fancy a tinfoil hat.
- Multiple pods can be easily spun up. Example usecase, 2 pods, one with projects to work on using local LLMs only, another with allowed access to both local and external providers.

## Prerequisites

- **Podman** and **podman-compose**: `sudo apt install podman podman-compose`
- TUI coding agents misbehave when you copy/paste from them when they're running inside any container. Use a terminal emulator that handles this properly, e.g. [kitty](https://github.com/kovidgoyal/kitty) `host-tools/setup-kitty.sh`.
- You can run the scripts from `host-tools` to have a batteries included setup. They can setup Kitty, download agent binaries for the pods like opencode, pi, maki, herdr, agent-browser, configure ezsh for pods etc.
---

## Quick Start (run the shipped `agents` pod)

The fastest way to get a working, isolated pod. Run from the project root (the `contained-pods` directory):

```bash
# 0. One-time: install prerequisites
sudo apt install podman podman-compose

# 1. Give the container's 'poduser' account a password (used for sudo inside).
export PODUSER_PASSWORD='replace-with-a-password'

# 2. One-time: build the base image
podman-compose -f compose.yaml build

# 3. One-time: create the shared external network
podman network create internet-net

# 4. REVIEW AND ALLOW THE NETWORK SOURCES YOU NEED FOR THIS CONTAINFED (default only allows APT sources and HOST:8085 everyting else is denied)
nano mypods/agents/proxy/squid.conf

# 5. Build and start the agents pod (container + proxy)
cd mypods/agents

# On Ubuntu 26.04 or Debian 13, or any newer OS with Podman ≥ 5.0
podman-compose --in-pod false up -d --build

# On Ubuntu 24.04 and older versions of Podman use:
# podman-compose up -d --build

# If you get error: --userns and --pod cannot be set together, run:
# podman-compose down && podman-compose --in-pod false up -d --build

# 6. Verify both containers are running
podman ps -a
#    You should see:  agents-contained   and   agents-contained-proxy

# 7. Jump inside the pod as 'poduser'
podman exec -it --user poduser agents-contained bash
```

You're in. From inside the pod:

- Your code lives at `/home/poduser/projects`
- Shared configs are at `/home/poduser/config` (read-only)
- `sudo` works with the password you set in step 1
- **All outbound traffic is blocked by default** — only the domains listed in `mypods/agents/proxy/squid.conf` are reachable. Edit that file and run `podman-compose restart` (inside `mypods/agents`) to apply changes.

> Optional, after the pod is running: prep agent binaries, shell aliases and Kitty on the host with the `host-tools/*.sh` scripts. See [`host-tools/README.md`](host-tools/README.md).

---

## Squid Log Viewer

`logviewer` is a setup to view the traffic requests from your pods using the Squid access logs. It shows Squid access logs requests, what requests are being sent, what is being blocked. Actually see what requests your tools/agents are attempting. Run the tiny `logserver.py` helper:

```bash
cd contained-pods
sudo python3 logserver.py --port 8090
```

Then open http://127.0.0.1:8090/ it auto-discovers every container's `proxy/logs/squid-access.log`.

![Log Server](https://raw.githubusercontent.com/jotyGill/contained-pods/main/assets/logserver.png)

Why not open `logviewer.html` directly? Proxy pods write logs owned by a different UID, so browsers couldn't read them even with world-read permissions. (I tried different approaches, but this setup needs: rootless podman + a DNS server running on the proxy's port 53 + UID 1000 mapping for seamless file permission). Run this helper as root using `sudo`.

---

<details>
<summary><b>Full Setup Guide For Multiple Variants</b></summary>

How to create and run an isolated container/pod variant.

### Overview

1. Set the `PODUSER_PASSWORD` environment variable
2. Build the base image (`localhost/contained-pods:latest`)
3. Create the shared `internet-net` network (one-time)
4. Create a new variant
5. Review and customize the proxy allowlist (`mypods/<variant-name>/proxy/squid.conf`)
6. Build and start the pod variant
7. Verify that the new pod variant is running
8. Access the pod

---

### 1. Set the Password

The `PODUSER_PASSWORD` environment variable is used during the base image build to set the password for the `poduser` account. This password is also used for `sudo` access.
```bash
# Set the password for your containers 'poduser'
export PODUSER_PASSWORD='your_password_here'
```

---

### 2. Build the Base Image

The base image (`localhost/contained-pods:latest`) must be built first, as all variant Dockerfiles inherit from it. Run this from the project root (the `contained-pods` directory):
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

### 4. Create a New Variant from the Template

To create a new isolated pod, copy the `template-proxied` directory and customize it:

```bash
# Copy the template
cp -r mypods/template-proxied mypods/myvariant
```

Set your pod `VARIANT` name in the variant's `.env` file:

```bash
cd mypods/myvariant
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

### 5. Review and Customize the Proxy Allowlist (`proxy/squid.conf`)

**REQUIRED**: Define which domains/IPs this variant can access. By default, all outbound traffic is blocked.

```bash
nano mypods/<variant-name>/proxy/squid.conf
```

Example allowlist:
```conf
# Allow access to a local LLM (Llama.cpp) at 192.168.0.50:8080
acl allowed_internal dst 192.168.0.50
acl allowed_internal_port port 8080
http_access allow allowed_internal allowed_internal_port

# Allow access to PyPI
acl allowed dstdomain .pypi.org
acl allowed dstdomain .pythonhosted.org
http_access allow allowed

# Deny everything else
http_access deny all
```

---

### 6. Build and Start the Variant

Build the variant image and start both the container and its proxy:

```bash
cd mypods/<variant-name>
podman-compose --in-pod false up -d --build
```

---

### 7. Verify Everything is Running

Check that both containers are up and running:

```bash
# List all running containers
podman ps -a

# You should see both:
# - <variant>-contained
# - <variant>-contained-proxy
```

If the container can't reach allowed domains, check:
1. Is the proxy running? (`podman ps -a`)
2. Does `squid.conf` have the correct allowlist entries?
3. Was the proxy restarted after editing `squid.conf`?

---

### 8. Access the Container

Access the container directly using `podman exec`.

```bash
podman exec -it --user poduser <variant>-contained bash
```

Once inside, you can:
- Access your projects at `/home/poduser/projects`
- Use shared configs at `/home/poduser/config`
- Use `sudo` with the password you set in Step 1
- Install packages (in the template, APT sources are allowed, nothing else is allowed by default)

---
</details>

<details>
<summary><b>Managing Variants</b></summary>

### Changing Proxy Rules

After editing `mypods/<variant-name>/proxy/squid.conf`, restart those pods to apply changes.

### Starting / Stopping

```bash
cd mypods/<variant-name>
# Stop containers (preserves data)
podman-compose stop
# Start again
podman-compose start
```

### Rebuilding After Changes

If you modify the variant's `Dockerfile`:

```bash
# Rebuild variant
cd mypods/<variant-name>
# Stop and remove containers. Data in ~/projects is still preserved, everyting else
podman-compose down
podman-compose --in-pod false up -d --build
```

---
</details>

<details>
<summary><b>Project Structure</b></summary>

```
contained-pods/
├── Dockerfile                 # Base image (tools, user setup)
├── compose.yaml               # Builds base image (needs PODUSER_PASSWORD build arg)
├── logserver.py               # Optional helper: serves logviewer + auto-discovers logs
├── logviewer.html             # Log viewer frontend (served by logserver.py)
├── set-proxy-dns.sh           # DNS-isolation entrypoint for the base image
├── host-tools/                # Host setup scripts (kitty, agent binaries, etc.)
├── config/                    # Shared configs mounted as read-only to /home/poduser/config
│   └── ...                    # Shell settings, aliases, env vars, etc.
├── proxy/
│   └── Dockerfile             # Squid proxy image (runs dnsmasq + squid)
└── mypods/
    ├── template-proxied/      # TEMPLATE: copy this to create a new variant pod
    │   ├── .env               # VARIANT=template-proxied
    │   ├── Dockerfile         # Variant dockerfile (FROM localhost/contained-pods:latest)
    │   ├── compose.yaml
    │   ├── proxy/
    │   │   ├── squid.conf     # ⚠️ MUST REVIEW: Allowlist domains/IPs for your variant
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
</details>

<details>
<summary><b>Network Architecture</b></summary>

Each variant uses two networks to enforce isolation:

- **Internal network** (`${VARIANT}-contained-net`) — container can only reach its own squid proxy, not the internet directly
- **External network** (`internet-net`) — only the squid proxy connects here to forward allowed traffic

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

### Traffic Containment

The proxy runs its own `dnsmasq` and squid's `squid.conf` is configured with `dns_nameservers 127.0.0.1`, so all DNS resolution for the pod is funneled through the proxy's allowlist. The container reaches the proxy via `${VARIANT}-contained-proxy:3128`.

### Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│           ${VARIANT}-contained-net  (internal network)                  │
│                                                                         │
│   ┌──────────────────────┐               ┌────────────────────────┐     │
│   │     Container        │               │        Proxy           │     │
│   │     (poduser)        │               │                        │     │
│   │                      │               │                        │     │
│   │ ${VARIANT}-contained │  ──────────▶  │ ${VARIANT}-contained-  │     │
│   │                      │   port 3128   │      proxy             │     │
│   │                      │  ◀──────────  │          │             │     │
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
</details>

<details>
<summary><b>How Proxies Work</b></summary>

Each variant has its own `proxy/squid.conf` that defines an **allowlist** of domains/IPs. **By default, all traffic is blocked**.

To allow a domain (e.g., GitHub for code):
```conf
acl allowed dstdomain .github.com
http_access allow allowed
```

If you need to change proxy rules, edit the `mypods/<variant>/proxy/squid.conf` for that container, then restart the containers:

```bash
cd mypods/<variant-name>
# Stop containers (preserves data)
podman-compose stop
# Start again
podman-compose start
```


---
</details>

<details>
<summary><b>Troubleshooting</b></summary>

| Issue | Fix |
|-------|-----|
| `localhost/contained-pods:latest` not found | Run `podman-compose -f compose.yaml build` from project root first |
| Container can't reach allowed domains | Check proxy is running: `podman ps \| grep proxy` |
| Proxy config changes not taking effect | Edit `proxy/squid.conf` then `podman restart <variant>-contained-proxy` then `podman restart <variant>-contained`|
| Build fails / password not set | Ensure `PODUSER_PASSWORD` is exported before building the base image |
| Variant won't start (network error) | Ensure `internet-net` exists: `podman network create internet-net` |
| `podman exec` access denied | Ensure `PODUSER_PASSWORD` was set correctly during base image build |

---
</details>

<details>
<summary><b>Tips</b></summary>

- Each variant has its own `projects/` folder — it's mounted at `/home/poduser/projects` inside the container
- The `.env` file defines `VARIANT` — change it per variant; the variant name drives the container, proxy, network, and image names
- The `config/` directory is shared across all variants and mounted as read-only at `/home/poduser/config` — put shell aliases, environment variables, or any container-wide configs here
- Use `podman-compose logs -f` to follow container logs in real-time
- The proxy logs are available at `mypods/<variant>/proxy/logs/` on the host

---
</details>

## License

This project is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html) (GPLv3).
