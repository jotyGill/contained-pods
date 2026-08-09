# Host Tools

Scripts you run on the **host** (your machine), not inside a pod container.

| Script | Runs where | Purpose |
|--------|-----------|---------|
| `setup-kitty.sh` | host | Install the [kitty](https://github.com/kovidgoyal/kitty) terminal emulator from the latest release |
| `fetch-bins-for-pods.sh` | host | Download the latest versions of the static binaries (opencode,pi,maki etc) used by pods into `../config/bins/` |
| `setup-ezsh-from-host.sh` | host | Install ezsh into a folder for pods (`config/ez/ezsh-installed`) |

## Contrast with `config/`

- **`host-tools/`** run **on the host** to prepare the binaries, terminal, and shell to use later in pods.
- **`config/`** is mounted read-only into pods. Its scripts (`configure-pod.sh`, `ez/setup-ezsh-in-docker.sh`) run **inside** the container as `poduser`.

## Usage

```bash
# One-time host prep
cd host-tools
bash ./setup-kitty.sh
bash ./fetch-bins-for-pods.sh
bash ./setup-ezsh-from-host.sh
cp ./files-to-be-copied-into-config/configure-pod.sh ../config/

# configure-pod.sh is my example config, update it with your configs and files to want to use in the pods

# Then build a pod and configure it from inside (see project README)
podman exec -it --user poduser <variant>-contained zsh
bash /home/poduser/config/configure-pod.sh
bash /home/poduser/config/ez/setup-ezsh-in-pod.sh
```
