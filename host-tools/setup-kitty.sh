#!/usr/bin/env bash
# setup-kitty.sh — install kitty on the HOST from the latest GitHub release
# Run on the host (not inside a container).

set -euo pipefail

VER=$(curl -fsSL https://api.github.com/repos/kovidgoyal/kitty/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p') \
  && curl -fL "https://github.com/kovidgoyal/kitty/releases/download/v$VER/kitty-$VER-x86_64.txz" -o /tmp/k.txz \
  && rm -rf ~/.local/kitty.app \
  && mkdir -p ~/.local/kitty.app \
  && tar -xJf /tmp/k.txz -C ~/.local/kitty.app \
  && rm /tmp/k.txz

mkdir -p ~/.local/bin
ln -sf ~/.local/kitty.app/bin/kitty ~/.local/bin/kitty
ln -sf ~/.local/kitty.app/bin/kitten ~/.local/bin/kitten

echo "kitty $VER installed to ~/.local/kitty.app and symlinked into ~/.local/bin/"
echo 'If ~/.local/bin is not on your PATH. Add it with: export PATH="~/.local/bin:$PATH"'
