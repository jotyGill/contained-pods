#!/usr/bin/env bash
# configure-pod.sh — configure a pod from the shared config mount.
# Run inside the container as poduser:  bash /home/poduser/config/configure-pod.sh
# Idempotent: re-run any time to refresh the pod from the host's config.

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/config}"

# Agent config files live in agents/ (older setups: agentconfigfiles/).
AGENT_CONF_DIR="$CONFIG_DIR/agents"
[ -d "$AGENT_CONF_DIR" ] || AGENT_CONF_DIR="$CONFIG_DIR/agentconfigfiles"

# copy_if SRC DEST — copies an optional config file if present, else no-op.
copy_if() {
    if [ -f "$1" ]; then cp -f "$1" "$2"; fi
}

mkdir -p "$HOME/.ssh" "$HOME/.config/opencode" "$HOME/.pi/agent/skills" \
         "$HOME/.pi/agent/themes" "$HOME/.pi/agent/extensions" \
         "$HOME/.local/bin" "$HOME/.npm-global" "$HOME/.dsh"

# --- Bins: symlink bins/ onto PATH ------------------------------------------
# nullglob: an empty/missing bins/ must not link the literal glob.
# Dirs (piold/, backups) and *.tmp.* leftovers from interrupted fetches are
# skipped; ln -sfn replaces stale symlinks-to-dirs instead of linking in them.
shopt -s nullglob
for bin in "$CONFIG_DIR"/bins/*; do
    base="$(basename "$bin")"
    [ -d "$bin" ] && continue
    case "$base" in *.tmp.*) continue ;; esac
    ln -sfn "$bin" "$HOME/.local/bin/$base"
done

# Prune links from earlier runs whose bins/ target was removed or renamed.
# Only ever unlinks broken symlinks pointing into $CONFIG_DIR/bins/.
for link in "$HOME"/.local/bin/*; do
    if [ -L "$link" ] && [ ! -e "$link" ]; then
        case "$(readlink "$link")" in "$CONFIG_DIR"/bins/*) rm -f "$link" ;; esac
    fi
done

# --- Shared agent config ------------------------------------------------------
if [ -d "$AGENT_CONF_DIR/maki-config" ]; then
    mkdir -p "$HOME/.config/maki"
    cp -r "$AGENT_CONF_DIR/maki-config/." "$HOME/.config/maki/"
fi
for dir in skills extensions; do
    if [ -d "$AGENT_CONF_DIR/$dir" ]; then
        cp -r "$AGENT_CONF_DIR/$dir/." "$HOME/.pi/agent/$dir/"
    fi
done

copy_if "$CONFIG_DIR/configfiles/.gitconfig" "$HOME/.gitconfig"
copy_if "$AGENT_CONF_DIR/opencode.jsonc"          "$HOME/.config/opencode/opencode.jsonc"
copy_if "$AGENT_CONF_DIR/pimodels.config"         "$HOME/.pi/agent/models.json"
copy_if "$AGENT_CONF_DIR/pisettings.json"          "$HOME/.pi/agent/settings.json"
copy_if "$AGENT_CONF_DIR/catppuccin-mocha.json"   "$HOME/.pi/agent/themes/catppuccin-mocha.json"
copy_if "$AGENT_CONF_DIR/light.json"              "$HOME/.pi/agent/themes/light.json"
copy_if "$AGENT_CONF_DIR/rpc-extension-ui.ts"     "$HOME/.pi/agent/extensions/rpc-extension-ui.ts"
copy_if "$AGENT_CONF_DIR/dshsettings.yaml"        "$HOME/.dsh/settings.yaml"

# --- npm prefix (if npm is present) --------------------------------------------
if command -v npm >/dev/null 2>&1; then
    npm config set prefix "$HOME/.npm-global"
fi

echo "Pod configured from $CONFIG_DIR (agent configs: $AGENT_CONF_DIR)"
