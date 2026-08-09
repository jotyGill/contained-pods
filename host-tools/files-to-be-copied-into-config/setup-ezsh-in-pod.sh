#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EZSH_DIR="$SCRIPT_DIR/ezsh-installed"

# Validate installation
[ -d "$EZSH_DIR" ] || { echo "ERROR: ezsh-installed not found at $EZSH_DIR"; exit 1; }

# If doesn't exist
mkdir -p "$HOME/.config"
mkdir -p "$HOME/.local/bin"

# Create symlinks (force overwrite non-symlink files/dirs)
link() {
    local target="$1" link="$2"
    if [ -e "$link" ] && [ ! -L "$link" ]; then
        rm -rf "$link"
    fi
    ln -sf "$target" "$link"
}

#Only create symlink if ~/.config/ezsh doesn't exist
[ ! -e "$HOME/.config/ezsh" ] && link "$EZSH_DIR" "$HOME/.config/ezsh"

# Core symlinks
link "$EZSH_DIR/.zshrc" "$HOME/.zshrc"
## [ -d "$EZSH_DIR/.cache/zsh" ] &&  link "$EZSH_DIR/.cache/zsh" "$HOME/.cache/zsh"
mkdir -p "$HOME/.cache/zsh"
[ -d "$EZSH_DIR/.fonts" ] && link "$EZSH_DIR/.fonts" "$HOME/.fonts"
[ -f "$EZSH_DIR/todo/todo.cfg" ] && link "$EZSH_DIR/todo/todo.cfg" "$HOME/.todo.cfg"

# Create fzf binary symlink in ~/.local/bin
if [ -f "$EZSH_DIR/fzf/bin/fzf" ]; then
    link "$EZSH_DIR/fzf/bin/fzf" "$HOME/.local/bin/fzf"
fi
# Generate fzf config
[ -f "$EZSH_DIR/fzf/bin/fzf" ] && "$EZSH_DIR/fzf/bin/fzf" --zsh > "$HOME/.fzf.zsh"

# Build fzf-tab
FZF_TAB="$EZSH_DIR/oh-my-zsh/custom/plugins/fzf-tab/fzf-tab.plugin.zsh"
[ -f "$FZF_TAB" ] && [ -x "$(command -v zsh)" ] && \
    PATH="$EZSH_DIR/fzf/bin:$PATH" zsh -c "source '$FZF_TAB' && build-fzf-tab-module" 2>/dev/null || true

# set zsh as default shell
chsh -s /usr/bin/zsh

echo "Setup complete. exec zsh"
