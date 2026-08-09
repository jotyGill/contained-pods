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

# --- Directories: copy contents into the target dir (not as a subdir) ---
cp -r "$CONFIG_DIR/agents/maki-config/."     /home/poduser/.config/maki/
cp -r "$CONFIG_DIR/agents/skills/."          /home/poduser/.pi/agent/skills/

# --- Files (copy, preserving path/name like the old symlinks) ---
cp -f "$CONFIG_DIR/configfiles/.gitconfig"        /home/poduser/.gitconfig

cp -f "$CONFIG_DIR/agents/opencode.jsonc"          /home/poduser/.config/opencode/opencode.jsonc
cp -f "$CONFIG_DIR/agents/pimodels.config"         /home/poduser/.pi/agent/models.json
cp -f "$CONFIG_DIR/agents/pisettings.json"         /home/poduser/.pi/agent/settings.json
cp -f "$CONFIG_DIR/agents/catppuccin-mocha.json"   /home/poduser/.pi/agent/themes/catppuccin-mocha.json

# --- npm prefix (if npm is present) ---
command -v npm >/dev/null 2>&1 && npm config set prefix ~/.npm-global

echo "Pod config copied from $CONFIG_DIR"
