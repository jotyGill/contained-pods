#!/bin/bash
#
# ezsh Offline Installer ro run on the host for contained-pods containers
# Installs ezsh to specified directory without modifying host home.
# All components are self-contained for docker/podman container use.

set -e

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --dir PATH    Installation directory (default: ../config/ez/ezsh-installed)"
    echo "  -h, --help   Show this help message"
    exit 0
}

INSTALL_DIR="../config/ez/ezsh-installed"
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage ;;
        --dir) INSTALL_DIR="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

EZSH_CONFIG_DIR="$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
EZSH_REPO_DIR="$INSTALL_DIR/../ezsh"  # Clone ezsh to script's directory, not parent

# Ensure ezsh repo exists (clone if missing, pull if exists)
if [ ! -d "$EZSH_REPO_DIR" ]; then
    git clone https://github.com/jotyGill/ezsh "$EZSH_REPO_DIR"
else
    (cd "$EZSH_REPO_DIR" && git pull --quiet)
fi

# Verify ezsh repo has required files
if [ ! -f "$EZSH_REPO_DIR/.zshrc" ] || [ ! -f "$EZSH_REPO_DIR/ezshrc.zsh" ] || [ ! -f "$EZSH_REPO_DIR/p10k.zsh" ]; then
    echo "ERROR: ezsh repo incomplete at $EZSH_REPO_DIR" >&2
    exit 1
fi

# Check dependencies
for cmd in git wget; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd required" >&2; exit 1; }
done

# Create directories (but NOT oh-my-zsh - we'll clone that separately)
mkdir -p "$EZSH_CONFIG_DIR"/{zshrc,.cache/zsh,.fonts,bin}

# Copy ezsh configs
cp -f "$EZSH_REPO_DIR"/{.zshrc,ezshrc.zsh,p10k.zsh} "$EZSH_CONFIG_DIR/"

# Install oh-my-zsh (handle existing dir properly)
OH_MY_ZSH_DIR="$EZSH_CONFIG_DIR/oh-my-zsh"
if [ -d "$OH_MY_ZSH_DIR" ]; then
    if [ -d "$OH_MY_ZSH_DIR/.git" ]; then
        (cd "$OH_MY_ZSH_DIR" && git pull --quiet)
    else
        echo "Removing existing non-git oh-my-zsh directory..."
        rm -rf "$OH_MY_ZSH_DIR"
    fi
fi

if [ ! -d "$OH_MY_ZSH_DIR" ]; then
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$OH_MY_ZSH_DIR"
fi

# Generic plugin installer
install_plugin() {
    local dir="$1" url="$2"
    if [ -d "$dir/.git" ]; then (cd "$dir" && git pull --quiet)
    else git clone --depth=1 "$url" "$dir"; fi
}

# Install plugins/themes
install_plugin "$EZSH_CONFIG_DIR/oh-my-zsh/plugins/zsh-autosuggestions" https://github.com/zsh-users/zsh-autosuggestions
install_plugin "$EZSH_CONFIG_DIR/oh-my-zsh/custom/plugins/zsh-syntax-highlighting" https://github.com/zsh-users/zsh-syntax-highlighting.git
install_plugin "$EZSH_CONFIG_DIR/oh-my-zsh/custom/plugins/zsh-completions" https://github.com/zsh-users/zsh-completions
install_plugin "$EZSH_CONFIG_DIR/oh-my-zsh/custom/plugins/zsh-history-substring-search" https://github.com/zsh-users/zsh-history-substring-search
install_plugin "$EZSH_CONFIG_DIR/oh-my-zsh/custom/themes/powerlevel10k" https://github.com/romkatv/powerlevel10k.git
install_plugin "$EZSH_CONFIG_DIR/oh-my-zsh/custom/plugins/k" https://github.com/supercrabtree/k
install_plugin "$EZSH_CONFIG_DIR/oh-my-zsh/custom/plugins/fzf-tab" https://github.com/Aloxaf/fzf-tab

# Install fzf binary (Linux x86_64 only, wget only)
download_fzf() {
    local dir="$EZSH_CONFIG_DIR/fzf/bin"
    mkdir -p "$dir"
    version="0.74.2"

    echo "Downloading fzf ($version)..."
    wget -q "https://github.com/junegunn/fzf/releases/download/v$version/fzf-$version-linux_amd64.tar.gz" -O - | tar -xz -C "$dir" fzf
    chmod +x "$dir/fzf"
    echo "✓ fzf binary installed at $dir/fzf"
}
download_fzf

# Install marker (copy marker.py to bin, don't run install.py)
install_marker() {
    local dir="$EZSH_CONFIG_DIR/marker"
    if [ -d "$dir/.git" ]; then (cd "$dir" && git pull --quiet)
    else git clone --depth=1 https://github.com/jotyGill/marker "$dir"; fi

    # Copy marker.py to bin
    [ -f "$dir/marker.py" ] && cp "$dir/marker.py" "$EZSH_CONFIG_DIR/bin/marker" 2>/dev/null || :
    chmod +x "$EZSH_CONFIG_DIR/bin/marker" 2>/dev/null || :
}
install_marker

# Install todo.txt-cli
install_todo() {
    local dir="$EZSH_CONFIG_DIR/todo" bin_dir="$EZSH_CONFIG_DIR/bin"
    if [ ! -f "$dir/todo.sh" ]; then
        mkdir -p "$dir" "$bin_dir"
        local tar="$EZSH_CONFIG_DIR/todo.txt_cli-2.12.0.tar.gz"
        wget -q --show-progress https://github.com/todotxt/todo.txt-cli/releases/download/v2.12.0/todo.txt_cli-2.12.0.tar.gz -O "$tar" || exit 1
        tar xvf "$tar" -C "$dir" --strip 1 && rm "$tar" || exit 1
    fi
    # Create default config if missing
    [ -f "$dir/todo.cfg" ] || echo 'DATA="$HOME/.todo"
LOCK_WAIT=60' > "$dir/todo.cfg"
    ln -sf "$dir/todo.sh" "$bin_dir/todo.sh"
}
install_todo

# Install Nerd Fonts
install_fonts() {
    local dir="$EZSH_CONFIG_DIR/.fonts" base="https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts"
    mkdir -p "$dir"
    for font in HackNerdFont-Regular.ttf RobotoMonoNerdFont-Regular.ttf DejaVuSansMNerdFont-Regular.ttf; do
        [ -f "$dir/$font" ] || wget -q --show-progress "$base/${font%%NerdFont*}/${font}" -P "$dir" 2>/dev/null || :
    done
}
install_fonts

cp -f "$(dirname "$0")/files-to-be-copied-into-config/setup-ezsh-in-pod.sh" "$(dirname "$0")/../config/ez/setup-ezsh-in-pod.sh"

echo "Installation complete. ezsh installed to: $EZSH_CONFIG_DIR"
echo "In pods: run config/ez/setup-ezsh-in-pod.sh to configure them to use ezsh."
