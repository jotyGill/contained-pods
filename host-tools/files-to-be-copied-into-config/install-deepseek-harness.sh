#!/usr/bin/env bash
# Install Node LTS + pnpm + the DeepSeek Harness CLI into ~/.local (no root).
# Idempotent; dsh is bumped to @latest on every run.
# Start the web UI with ./run-deepseek-harness.sh.
#
# Usage: ./install-deepseek-harness.sh [--proxy URL | --no-proxy]
# No host, address, or proxy is baked in: the proxy comes from the environment
# or --proxy, and an empty one means direct egress.
set -euo pipefail

LOCAL="$HOME/.local"
NODE_DIR="$LOCAL/node"
BIN="$NODE_DIR/bin"

# Egress proxy for downloads, used as env for this run only (nothing is
# persisted to ~/.npmrc).
PROXY="${https_proxy:-${http_proxy:-}}"
while [[ $# -gt 0 ]]; do
  case $1 in
    --proxy)    [[ $# -ge 2 ]] || { echo "--proxy needs a value" >&2; exit 1; }
                PROXY=$2; shift 2 ;;
    --no-proxy) PROXY=""; shift ;;
    -h|--help)  sed -n '2,8p' "$0"; exit 0 ;;
    *)          echo "unknown argument: $1 (see: $0 --help)" >&2; exit 1 ;;
  esac
done
if [[ -n $PROXY ]]; then
  export http_proxy="$PROXY" https_proxy="$PROXY"
  export no_proxy="${no_proxy:-localhost,127.0.0.1}"
fi
export NODE_USE_ENV_PROXY=1   # node's fetch honors proxy env vars
export PATH="$BIN:$PATH"

# npm without a persisted proxy config.
npm_raw() { npm --proxy= --https-proxy= "$@"; }

# 1. Node LTS from the official tarball.
if command -v node >/dev/null 2>&1; then
  echo "==> Node $(node -v) already installed"
else
  echo "==> Installing Node.js LTS to $NODE_DIR"
  ARCH=$(uname -m); case $ARCH in
    x86_64) NODE_ARCH=x64 ;;
    aarch64 | arm64) NODE_ARCH=arm64 ;;
    *) echo "unsupported architecture: $ARCH" >&2; exit 1 ;;
  esac
  VER=$(curl -fsS https://nodejs.org/dist/index.json |
    python3 -c 'import json,sys; print(next(v["version"] for v in json.load(sys.stdin) if v.get("lts")))')
  [[ -n $VER ]] || { echo "no LTS version found at nodejs.org" >&2; exit 1; }
  FILE="node-${VER}-linux-${NODE_ARCH}.tar.xz"
  TMP_XZ="/tmp/$FILE"; TMP_DIR="$LOCAL/extract.$$"
  rm -rf "$TMP_DIR"; mkdir -p "$TMP_DIR"
  curl -fL --retry 3 -o "$TMP_XZ" "https://nodejs.org/dist/$VER/$FILE"
  ( cd /tmp && curl -fsS "https://nodejs.org/dist/$VER/SHASUMS256.txt" |
      grep -F " $FILE" | sed 's/ \*/  /' | sha256sum -c - )
  # Extract with python3: this image has no xz binary. filter=data rejects
  # absolute paths / .. members.
  python3 - "$TMP_XZ" "$TMP_DIR" <<'PY'
import lzma, sys, tarfile
with lzma.open(sys.argv[1]) as src, tarfile.open(fileobj=src) as tar:
    tar.extractall(sys.argv[2], filter="data")
PY
  # Replace an existing install only after the new one is verified.
  [[ -e "$NODE_DIR" ]] && mv "$NODE_DIR" "$LOCAL/.node.old.$$"
  mv "$TMP_DIR/node-${VER}-linux-${NODE_ARCH}" "$NODE_DIR"
  rm -rf "$TMP_DIR" "$LOCAL/.node.old.$$" "$TMP_XZ"
  grep -qF '.local/node/bin' ~/.bashrc ||
    echo 'export PATH="$HOME/.local/node/bin:$PATH"' >> ~/.bashrc
  grep -qF NODE_USE_ENV_PROXY ~/.bashrc ||
    echo 'export NODE_USE_ENV_PROXY=1' >> ~/.bashrc
  echo "==> Installed $(node -v)"
fi

# 2. pnpm. Corepack shims bypass the proxy, so drop them first.
if command -v pnpm >/dev/null 2>&1; then
  echo "==> pnpm $(pnpm -v) already installed"
else
  echo "==> Installing pnpm"
  rm -f "$BIN"/pnpm "$BIN"/pnpx "$BIN"/yarn "$BIN"/yarnpkg
  npm_raw i -g pnpm
  echo "==> Installed pnpm $(pnpm -v)"
fi

# 3. Harness CLI. Skip the network when already at the latest published version.
WANT=$(npm_raw view @deepseek-ai/dsh version)
HAVE=$(dsh --version 2>/dev/null || echo none)
if [[ $HAVE == "$WANT" ]]; then
  echo "==> dsh $HAVE already latest"
else
  echo "==> Installing @deepseek-ai/dsh@$WANT (have: $HAVE)"
  npm_raw i -g @deepseek-ai/dsh@latest
  echo "==> Installed dsh $(dsh --version)"
fi

echo "==> All done. Start the web UI with:"
echo "    ./run-deepseek-harness.sh -u USER --pass-stdin --host ADDR"
