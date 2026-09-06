# Host Tools

Prep scripts for the pods. Some run on the **host**; others are copied into `config/` 
to run **inside** the container as `poduser`.

## Host scripts

Scripts to run **on the host** to prepare the binaries, terminal, and shell to use later in pods, or stage in-pod scripts to copy into `config/`:

| Script | Runs where | Purpose |
|--------|-----------|---------|
| `setup-kitty.sh` | host | Install the [kitty](https://github.com/kovidgoyal/kitty) terminal emulator from the latest release |
| `fetch-bins-for-pods.sh` | host | Download the latest versions of the static binaries (opencode, pi, maki, ...) used by pods into `../config/bins/` |
| `setup-ezsh-from-host.sh` | host | Install ezsh into a folder for pods (`config/ez/ezsh-installed`) |

## In-pod scripts

These live in `files-to-be-copied-into-config/` and are copied into `config/`
(read only mounted at `/home/poduser/config`), where they need to be run **inside** the container as
`poduser`:

| Script | Runs where | Purpose |
|--------|-----------|---------|
| `configure-pod.sh` | pod | Copy user config files and symlink `bins/` into the pod home |
| `setup-ezsh-in-pod.sh` | pod | Install ezsh inside the container |
| `install-deepseek-harness.sh` | pod | Install Node LTS + pnpm + the [DeepSeek Harness](https://github.com/deepseek-ai/dsh) CLI (`dsh`) into `~/.local` |
| `run-deepseek-harness.sh` | pod | Run the `dsh` web UI, relaying TLS + Basic auth in front of it |

## Usage

```bash
# One-time host prep
cd host-tools
bash ./setup-kitty.sh
bash ./fetch-bins-for-pods.sh
bash ./setup-ezsh-from-host.sh
cp -r ./files-to-be-copied-into-config/* ../config/

# configure-pod.sh is my example config, update it with your configs and files to want to use in the pods

# Then build a pod and configure it from inside (see project README)
podman exec -it --user poduser <variant>-contained zsh
bash /home/poduser/config/configure-pod.sh
bash /home/poduser/config/ez/setup-ezsh-in-pod.sh
```

## DeepSeek Harness

Run inside the pod. This setup installs and bolts **TLS (self-signed by default) + HTTP Basic auth on top of dsh's own `/api` launch token**.

*Requirement* : the pod needs to be able to access NPM related repos to install npm and deepseek-harness; uncomment NPM related domains in your pod e.g. mypods/agents/proxy/squid.conf.

```bash
# NPM
acl allowed dstdomain .npmjs.com
acl allowed dstdomain .npmjs.org
acl allowed dstdomain .nodejs.org
```

Restart the pods after.
```bash
cd mypods/agents/
podman-compose restart
```

```bash
podman exec -it --user poduser agents-contained bash

# copy the scripts to a writable folder (e.g. ~/projects) and run there
cp /home/poduser/config/install-deepseek-harness.sh /home/poduser/config/run-deepseek-harness.sh ~/projects/
cd ~/projects/
bash ./install-deepseek-harness.sh
bash ./run-deepseek-harness.sh -u user --pass-stdin --host-ip 192.168.1.50   # host-ip is your HOST's local IP, password on stdin
# => Open link from the host including the token : https://192.168.1.50:3080/?token=...
# stop: ./run-deepseek-harness.sh stop
```
