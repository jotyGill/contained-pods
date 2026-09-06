#!/usr/bin/env bash
# Configure a pod container by COPYING shared config files and SYMLINKING bins into the pod home
# Run inside the container as the pod user (poduser).

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/home/poduser/config}"

# Create target directories
mkdir -p /home/poduser/.ssh/
mkdir -p /home/poduser/.config/opencode
mkdir -p /home/poduser/.pi/agent/
mkdir -p /home/poduser/.pi/agent/themes/
mkdir -p /home/poduser/.local/bin/
mkdir -p ~/.npm-global

# --- Binaries: symlink every entry in bins/ into ~/.local/bin/ ---
mkdir -p /home/poduser/.local/bin/
for bin in "$CONFIG_DIR"/bins/*; do
    base="$(basename "$bin")"
    [ "$base" = "." ] && continue
    [ "$base" = ".." ] && continue
    ln -sf "$bin" /home/poduser/.local/bin/
done

# --- Directories: copy config contents into the target dirs ---
if [ -d "$CONFIG_DIR/agentconfigfiles/maki-config" ]; then
    mkdir -p /home/poduser/.config/maki
    cp -r "$CONFIG_DIR/agentconfigfiles/maki-config/." /home/poduser/.config/maki/
fi
if [ -d "$CONFIG_DIR/agentconfigfiles/skills" ]; then
    cp -r "$CONFIG_DIR/agentconfigfiles/skills/." /home/poduser/.pi/agent/skills/
fi

# --- Files: copy your config files into a given pod to have unified setup in many pods ---
[ -f "$CONFIG_DIR/configfiles/.gitconfig" ] && cp -f "$CONFIG_DIR/configfiles/.gitconfig" /home/poduser/.gitconfig

[ -f "$CONFIG_DIR/agentconfigfiles/opencode.jsonc" ] && cp -f "$CONFIG_DIR/agentconfigfiles/opencode.jsonc" /home/poduser/.config/opencode/opencode.jsonc
[ -f "$CONFIG_DIR/agentconfigfiles/pimodels.config" ] && cp -f "$CONFIG_DIR/agentconfigfiles/pimodels.config" /home/poduser/.pi/agent/models.json
[ -f "$CONFIG_DIR/agentconfigfiles/pisettings.json" ] && cp -f "$CONFIG_DIR/agentconfigfiles/pisettings.json" /home/poduser/.pi/agent/settings.json
[ -f "$CONFIG_DIR/agentconfigfiles/catppuccin-mocha.json" ] && cp -f "$CONFIG_DIR/agentconfigfiles/catppuccin-mocha.json" /home/poduser/.pi/agent/themes/catppuccin-mocha.json

# --- dsh (DeepSeek Harness) settings ---
mkdir -p /home/poduser/.dsh
[ -f "$CONFIG_DIR/agentconfigfiles/dshsettings.yaml" ] && cp -f "$CONFIG_DIR/agentconfigfiles/dshsettings.yaml" /home/poduser/.dsh/settings.yaml

# --- npm prefix (if npm is present) ---
command -v npm >/dev/null 2>&1 && npm config set prefix ~/.npm-global

echo "Pod config copied from $CONFIG_DIR"
