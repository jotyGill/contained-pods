#!/usr/bin/env bash
# fetch-dev-bins.sh — download the latest release of static binaries for pods. opencode,pi,make,rtk,agent-browser,herdr
# Run on the HOST. Places binaries into ../config/bins/ (mounted read-only into pods).
#
# Each tool is fetched from the latest GitHub release of its repo. The matching
# asset is selected by a regex against the release asset names. Archives are
# extracted; bare binaries are dropped in place.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINS_DIR="$SCRIPT_DIR/../config/bins"
mkdir -p "$BINS_DIR"

# Tool entries: name | repo | asset-regex | extract(true/false) | outname(optional)
TOOLS=(
  "opencode|anomalyco/opencode|opencode-linux-x64\\.tar\\.gz$|true|"
  "pi|earendil-works/pi|pi-linux-x64\\.tar\\.gz$|true|"
  "maki|tontinton/maki|x86_64-unknown-linux-musl\\.tar\\.gz$|true|"
  "rtk|rtk-ai/rtk|rtk-x86_64-unknown-linux-musl\\.tar\\.gz$|true|"
  "agent-browser|vercel-labs/agent-browser|agent-browser-linux-x64$|false|agent-browser"
  "herdr|herdrdev/herdr|herdr-linux-x86_64$|false|herdr"
)

api_latest_asset() {
  # $1 = owner/repo   $2 = asset regex
  # prints the download URL of the first asset matching regex in the latest release
  local repo="$1" regex="$2" api url
  api="https://api.github.com/repos/$repo/releases"
  # Prefer "latest" endpoint; fall back to listing releases if it 404s
  url="$api/latest"
  local json
  json="$(curl -fsSL "$url" || curl -fsSL "$api?per_page=1" | head -c 100000)"
  echo "$json" \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed -E 's/"browser_download_url": *"([^"]*)"/\1/' \
    | grep -E "$regex" \
    | head -n 1
}

for entry in "${TOOLS[@]}"; do
  IFS='|' read -r name repo regex extract outname <<< "$entry"

  # Download one binary at a time; pause 2s between each to be gentle on the host/API.
  sleep 2

  echo "==> $name ($repo)"
  url="$(api_latest_asset "$repo" "$regex")"
  if [ -z "$url" ]; then
    echo "   ! no asset matching /$regex/ found in latest release of $repo — skipping" >&2
    continue
  fi
  echo "   $url"

  tmp="$(mktemp)"
  curl -fL "$url" -o "$tmp"

  if [ "$extract" = "true" ]; then
    # Extract into a staging dir, then flatten into BINS_DIR
    stage="$(mktemp -d)"
    # try xz/tar; if it's a plain tar.gz the -J handles .gz too
    if tar -xJf "$tmp" -C "$stage" 2>/dev/null || tar -xzf "$tmp" -C "$stage" 2>/dev/null; then
      # find the first executable-like file and place it under $name
      found=""
      while IFS= read -r -d '' f; do
        if [ -z "$found" ] && [ -f "$f" ]; then
          found="$f"
        fi
      done < <(find "$stage" -type f -print0)
      if [ -n "$found" ]; then
        cp "$found" "$BINS_DIR/$name"
        chmod +x "$BINS_DIR/$name"
        echo "   extracted -> $BINS_DIR/$name"
      else
        echo "   ! no file found after extraction — leaving staged at $stage" >&2
      fi
    else
      echo "   ! failed to extract (not a recognized archive) — skipping" >&2
    fi
    rm -f "$tmp"
  else
    out="${outname:-$name}"
    mv "$tmp" "$BINS_DIR/$out"
    chmod +x "$BINS_DIR/$out"
    echo "   -> $BINS_DIR/$out"
  fi
done

echo "Done. Binaries in $BINS_DIR (mounted read-only into pods via configure-pod.sh)."
