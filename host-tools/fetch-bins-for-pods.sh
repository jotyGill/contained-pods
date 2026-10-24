#!/usr/bin/env bash
# fetch-bins-for-pods.sh — download the latest GitHub release binary of each
# tool below into ../config/bins/ (mounted read-only into pods;
# configure-pod.sh symlinks them onto PATH). Re-run any time to update.
#
# Entry: name | repo | asset-regex | extract(true/false) | outname(optional)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINS_DIR="$SCRIPT_DIR/../config/bins"
mkdir -p "$BINS_DIR"

TOOLS=(
  "opencode|anomalyco/opencode|opencode-linux-x64\\.tar\\.gz$|true|"
  "pi|earendil-works/pi|pi-linux-x64\\.tar\\.gz$|true|"
  "maki|tontinton/maki|x86_64-unknown-linux-musl\\.tar\\.gz$|true|"
  "rtk|rtk-ai/rtk|rtk-x86_64-unknown-linux-musl\\.tar\\.gz$|true|"
  "agent-browser|vercel-labs/agent-browser|agent-browser-linux-x64$|false|agent-browser"
  "herdr|herdrdev/herdr|herdr-linux-x86_64$|false|herdr"
)

# Latest-release download URL of the first asset matching $2 (repo in $1);
# falls back to listing releases if /latest 404s. The trailing || true makes
# a missing match yield empty output (reported by the caller) instead of
# tripping pipefail — also needed because head can SIGPIPE the grep upstream.
api_latest_asset() {
  local api="https://api.github.com/repos/$1/releases" json
  json="$(curl -fsSL "$api/latest" || curl -fsSL "$api?per_page=1" | head -c 100000)"
  echo "$json" \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed -E 's/"browser_download_url": *"([^"]*)"/\1/' \
    | grep -E "$2" | head -n 1 || true
}

# Place SRC at DEST via same-dir temp + atomic mv, so an interrupted run can
# never leave a half-written binary at DEST (mv from /tmp would not be atomic:
# different filesystems degrade it to copy+unlink).
place() {
  cp "$1" "$2.tmp.$$" && chmod +x "$2.tmp.$$" && mv -f "$2.tmp.$$" "$2"
}

for entry in "${TOOLS[@]}"; do
  IFS='|' read -r name repo regex extract outname <<< "$entry"
  out="${outname:-$name}"
  sleep 2   # gentle on the GitHub API

  echo "==> $name ($repo)"
  url="$(api_latest_asset "$repo" "$regex")"
  if [ -z "$url" ]; then
    echo "   ! no asset matching /$regex/ found in latest release of $repo — skipping" >&2
    continue
  fi
  echo "   $url"

  tmp="$(mktemp)"
  curl -fL "$url" -o "$tmp"
  found="$tmp"

  if [ "$extract" = "true" ]; then
    stage="$(mktemp -d)"
    if tar -xJf "$tmp" -C "$stage" 2>/dev/null || tar -xzf "$tmp" -C "$stage" 2>/dev/null; then
      # Prefer the member named like the tool; multi-file trees (the pi
      # release carries examples/, docs/, ...) otherwise yield junk files.
      found="$(find "$stage" -type f -name "$out" -print -quit)"
      [ -n "$found" ] || found="$(find "$stage" -type f -print -quit)"
      [ -n "$found" ] || { echo "   ! no file after extraction — staged at $stage" >&2; rm -f "$tmp"; continue; }
    else
      echo "   ! failed to extract (not a recognized archive) — skipping" >&2
      rm -f "$tmp"; continue
    fi
  fi

  # Never place onto a directory: cp/mv onto one drops the file *inside* it
  # and replaces nothing — how bins/pi silently rotted at 0.82.0 for weeks.
  if [ -d "$BINS_DIR/$out" ]; then
    echo "   ! $BINS_DIR/$out is a directory, not a binary — move it aside, then re-run" >&2
  else
    place "$found" "$BINS_DIR/$out"
    echo "   -> $BINS_DIR/$out"
  fi
  rm -f "$tmp"
done

echo "Done. Binaries in $BINS_DIR (symlinked into pods by configure-pod.sh)."
