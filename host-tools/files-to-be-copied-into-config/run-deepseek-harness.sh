#!/usr/bin/env bash
# What this does:
#   Deepseek Harness normally only listens on localhost interface and can't be easliy used from pods.
#   This script runs the DeepSeek Harness web UI (dsh) in the background and puts a proxy
#   with HTTPS using a self-signed certificate and password-protected
#   (Basic auth) access in front of it, so you can open the UI from the host
#   machine or any device on the network using the user/password you
#   provide. By default both the Basic auth user/password and the token URL
#   dsh prints at startup are needed to reach the web UI.
#   You can skip the token requirement by passing --no-token then visiting https://HOSTIP:3080/dsh
#
# Usage: ./run-deepseek-harness.sh -u USER [-p PASS] --host-ip ADDR [--port N] [--no-token] [dsh web args]
#        ./run-deepseek-harness.sh stop
set -euo pipefail

PUBLIC=3080           # relay port on 0.0.0.0; dsh uses PUBLIC+1 on loopback
BASIC_USER=""; BASIC_PASS=""; HOST=""
TLS_CERT=""; TLS_KEY=""; TLS_ENABLED=1   # TLS on by default; cert auto-generated
NO_TOKEN=0            # --no-token: /dsh auto-redirects to the token URL, bypassing it (Basic auth still needed); off by default

usage() {
  cat >&2 <<'EOF'
usage: ./run-deepseek-harness.sh -u USER [-p PASS] --host-ip ADDR [--port N] [--no-token] [dsh web args]
       ./run-deepseek-harness.sh stop
  -u, --user USER    Basic auth user
  -p, --pass PASS    Basic auth password (prompted for, hidden, if omitted)
  -i, --host-ip ADDR IP/hostname clients reach this box on (IPv4 or hostname)
      --no-token     Skip the token URL dsh prints at startup: /dsh redirects
                     straight to it, so Basic auth alone gets you in
      --port N       relay port (default 3080); dsh uses N+1 on loopback
      --tls-cert FILE TLS cert PEM (default $PWD/tls-cert.pem; self-signed if missing)
      --tls-key FILE  TLS key PEM  (default $PWD/tls-key.pem; generated if missing)
      --no-tls        serve plain HTTP instead of TLS (default is TLS)
  -h, --help         show this help
  Run needs: -u USER, -i/--host-ip ADDR, and a password (-p PASS, or a hidden
  interactive prompt when -p is omitted; a non-terminal stdin then fails).
EOF
  exit 1
}

args=(); stopping=0; port_given=
[[ $# -eq 0 ]] && usage
while [[ $# -gt 0 ]]; do
  case $1 in
    stop)           stopping=1; shift ;;
    -u|--user)      [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 1; }
                    BASIC_USER=$2; shift 2 ;;
    -p|--pass)      [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 1; }
                    BASIC_PASS=$2; shift 2 ;;
    -i|--host-ip)   [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 1; }
                    HOST=$2; shift 2 ;;
    --port)         [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 1; }
                    PUBLIC=$2; port_given=1; shift 2 ;;
    --tls-cert)     [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 1; }
                    TLS_CERT=$2; shift 2 ;;
    --tls-key)      [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 1; }
                    TLS_KEY=$2; shift 2 ;;
    --no-tls)       TLS_ENABLED=0; shift ;;
    --no-token)     NO_TOKEN=1; shift ;;
    -h|--help)      usage ;;
    *)              args+=("$1"); shift ;;
  esac
done

[[ $PUBLIC =~ ^[1-9][0-9]*$ ]] || { echo "--port must be a number: $PUBLIC" >&2; exit 1; }
(( PUBLIC <= 65534 )) || { echo "port $PUBLIC leaves no room for the internal port" >&2; exit 1; }
INTERNAL=$((PUBLIC + 1))

# Command-line patterns for process discovery. Anchored so this script's own
# cmdline never matches. The relay carries a unique argv marker.
DSH_PATTERN='^node .*/dsh web '
RELAY_MARKER="dsh-relay-$PUBLIC"
RELAY_PATTERN='^node -e .*'"$RELAY_MARKER"'$'
RELAY_STOP_PATTERN='^node -e .*dsh-relay-[0-9]+$'   # stop has no --port

# Live pids for a pattern; container PID 1 does not reap, so drop zombies.
find_pids() {
  local pid st
  for pid in $(pgrep -f "$1" 2>/dev/null || true); do
    [[ $pid == $$ ]] && continue
    st=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -n $st && $st != Z* ]] && echo "$pid"
  done
}

# TERM, wait, then KILL by process group (setsid gives each its own group).
stop_by() {
  local label=$1 pattern=$2 pids sig pid left
  pids=$(find_pids "$pattern")
  [[ -z $pids ]] && { echo "==> $label: nothing to stop"; return 0; }
  for sig in TERM KILL; do
    for pid in $pids; do kill -"$sig" -- "-$pid" 2>/dev/null || true; done
    if [[ $sig == TERM ]]; then
      for _ in $(seq 1 20); do
        left=$(find_pids "$pattern")
        [[ -z $left ]] && break
        sleep 0.5
      done
      [[ -z $left ]] && break
    fi
  done
  echo "==> $label: stopped ($(echo $pids | tr ' ' ','))"
}

if (( stopping )); then
  [[ -z $port_given && ${#args[@]} -eq 0 ]] || { echo "stop takes no other arguments" >&2; exit 1; }
  stop_by relay "$RELAY_STOP_PATTERN"
  stop_by dsh "$DSH_PATTERN"
  rm -f "$(dirname "$0")/dsh-token-url"   # stale token URL used by --no-token /dsh
  exit 0
fi

[[ -n $BASIC_USER ]] || { echo "missing --user (see: $0 --help)" >&2; exit 1; }
[[ -n $HOST ]] || { echo "missing --host-ip (see: $0 --help)" >&2; exit 1; }

# No -p: ask for the password with echo off, so it never lands in shell history
# or the process listing. Prompts go to stderr, keeping stdout clean. Without a
# terminal there is nobody to ask, so refuse rather than hang or read garbage.
if [[ -z $BASIC_PASS ]]; then
  [[ -t 0 ]] || { echo "no --pass given and stdin is not a terminal -- pass -p PASS" >&2; exit 1; }
  # bash sends the -p prompt to stderr on its own when stdin is a terminal.
  read -r -s -p "Set Password For Basic Auth: " BASIC_PASS || exit 1
  echo "" >&2
  [[ -n $BASIC_PASS ]] || { echo "empty password" >&2; exit 1; }
fi

export PATH="$HOME/.local/node/bin:$PATH"
export NODE_USE_ENV_PROXY=1    # node's fetch honors proxy env vars
command -v node >/dev/null 2>&1 || { echo "node not found -- run ./install-deepseek-harness.sh first" >&2; exit 1; }

cd "$(dirname "$0")"
LOG="$PWD/dsh.log"

# TLS: default on. Resolve cert/key paths, generating a self-signed cert here
# if none exists (openssl required then). With TLS on the relay listens for TLS
# only -- a cleartext HTTP request to that port gets no response at all.
# SCHEME drives the printed URL.
SCHEME=http
if (( TLS_ENABLED )); then
  TLS_CERT=${TLS_CERT:-$PWD/tls-cert.pem}
  TLS_KEY=${TLS_KEY:-$PWD/tls-key.pem}
  if [[ ! -e $TLS_CERT || ! -e $TLS_KEY ]]; then
    command -v openssl >/dev/null 2>&1 || {
      echo "no TLS cert at $TLS_CERT and openssl not found -- install openssl," >&2
      echo "pass --tls-cert/--tls-key, or use --no-tls" >&2; exit 1
    }
    san=DNS:$HOST
    [[ $HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && san=IP:$HOST
    echo "==> No TLS cert found -- generating self-signed for $HOST ($san)"
    openssl req -x509 -new -newkey rsa:2048 -nodes \
      -keyout "$TLS_KEY" -out "$TLS_CERT" -days 3650 \
      -subj "/CN=$HOST" -addext "subjectAltName=$san" 2>/dev/null
    chmod 600 "$TLS_KEY"
  fi
  [[ -r $TLS_CERT && -r $TLS_KEY ]] || {
    echo "cannot read TLS cert/key: $TLS_CERT / $TLS_KEY" >&2; exit 1; }
  SCHEME=https
fi

# Pid holding a LISTEN socket on a TCP port (field 10 of /proc/net/tcp is the
# socket inode, mapped back via /proc/*/fd). Prints nothing when free, else an
# owner pid or "unknown". Refuses to start while either port is in use, so a
# second start can't truncate the live log and strand the old server.
port_owner() {
  local hex inode fd pid
  hex=$(printf '%04X' "$1")
  inode=$(awk -v p="$hex" '$4 == "0A" {
      split($2, a, ":");
      if (a[2] == p && ($2 ~ /^(0100007F|00000000):/)) { print $10; exit }
    }' /proc/net/tcp 2>/dev/null)
  [[ -z $inode ]] && return 0
  for fd in /proc/[0-9]*/fd/*; do
    [[ $(readlink "$fd" 2>/dev/null) == "socket:[$inode]" ]] && { pid=${fd#/proc/}; echo "${pid%%/*}"; return 0; }
  done
  echo unknown
}

for port in $INTERNAL $PUBLIC; do
  owner=$(port_owner "$port")
  [[ -z $owner ]] || {
    echo "port $port is already in use (pid ${owner:-unknown}) -- stop with: $0 stop" >&2
    exit 1
  }
done

# Basic-auth gate in front of dsh: each request must present the credentials
# on its first header block, then the bytes are piped verbatim (the /api fence
# trusts the browser's real Host/Origin via --trusted-host). The credential
# arrives on stdin -- /proc/<pid>/environ and cmdline are world-readable.
RELAY_JS='
  const net = require("node:net"), tls = require("node:tls");
  const crypto = require("node:crypto"), fs = require("node:fs");
  // A Location value must stay a plain absolute http(s) URL: no control
  // characters or spaces (header injection), no markup, bounded length.
  const BAD = /[<>\x27"\\]/;
  const safeUrl = s =>
    s.length <= 2048 && /^[\x21-\x7e]+$/.test(s) && !BAD.test(s)
    && /^https?:\/\//.test(s) ? s : "";
  const p = Number(process.env.DSH_RELAY_PORT);
  const up = Number(process.env.DSH_UPSTREAM_PORT);
  let cred = "";
  process.stdin.setEncoding("latin1");
  process.stdin.on("data", d => { cred += d; });
  process.stdin.on("end", () => {
    cred = cred.split("\n", 1)[0].trim();
    if (!cred) { console.error("relay: empty credentials on stdin"); process.exit(1); }
    const want = Buffer.from("Basic " + Buffer.from(cred).toString("base64"));
    const eq = (a, b) => a.length === b.length && crypto.timingSafeEqual(a, b);
    const TC = process.env.DSH_TLS_CERT, TK = process.env.DSH_TLS_KEY;
    // TLS and plain listening are mutually exclusive: if a cert was named the
    // key must be there too, rather than quietly serving cleartext.
    if (Boolean(TC) !== Boolean(TK)) {
      console.error("relay: need both DSH_TLS_CERT and DSH_TLS_KEY (or neither)");
      process.exit(1);
    }
    // Only headers on replies the relay itself generates can be set here; the
    // proxied stream stays byte-verbatim so the /api Host/Origin fence holds.
    const HSTS = TC ? "Strict-Transport-Security: max-age=31536000\r\n" : "";
    // GET /dsh (behind Basic auth) redirects to the token URL, read per
    // request because the relay starts before dsh prints its token.
    const tokFile = process.env.DSH_TOKEN_FILE || "";
    const sopts = TC ? { cert: fs.readFileSync(TC), key: fs.readFileSync(TK) } : {};
    const server = (TC ? tls.createServer : net.createServer)(sopts, s => {
      let buf = Buffer.alloc(0);
      const onData = d => {
        buf = Buffer.concat([buf, d]);
        const end = buf.indexOf("\r\n\r\n");
        if (end === -1) { if (buf.length > 65536) s.destroy(); return; }
        const m = buf.subarray(0, end).toString("latin1").match(/^authorization:[ \t]*(.+?)[ \t]*$/im);
        if (m && eq(Buffer.from(m[1], "latin1"), want)) {
          s.removeListener("data", onData);
          if (tokFile) {
            const line = buf.subarray(0, end).toString("latin1").split("\r\n", 1)[0];
            if (line.startsWith("GET ") && line.split(" ")[1] === "/dsh") {
              let tokUrl = "";
              try {
                tokUrl = safeUrl(fs.readFileSync(tokFile, "latin1").split("\n", 1)[0].trim());
              } catch {}
              if (tokUrl) {
                s.end("HTTP/1.1 302 Found\r\nLocation: " + tokUrl + "\r\n" + HSTS +
                      "Content-Length: 0\r\nConnection: close\r\n\r\n");
                return;
              }
            }
          }
          const u = net.connect(up, "127.0.0.1");
          u.on("error", () => s.destroy());
          s.on("error", () => u.destroy());
          u.on("connect", () => { u.write(buf); s.pipe(u); u.pipe(s); });
        } else {
          s.end("HTTP/1.1 401 Unauthorized\r\n" +
                "WWW-Authenticate: Basic realm=\"dsh\"\r\n" + HSTS +
                "Content-Length: 0\r\nConnection: close\r\n\r\n");
          s.destroy();
        }
      };
      s.on("data", onData);
      s.on("error", () => s.destroy());
    });
    server.on("error", e => { console.error("relay:", e.message); process.exit(1); })
      .listen(p, "0.0.0.0");
  });
'

: > "$LOG"
chmod 600 "$LOG"   # the log holds the /api launch token
rm -f "$PWD/dsh-token-url"   # drop any token URL left over from an earlier run (e.g. a --no-token one)
echo "==> Starting dsh webui on 127.0.0.1:$INTERNAL"
setsid bash -c 'internal=$1; trust=$2; shift 2; \
  exec dsh web --no-open --port "$internal" --trusted-host "$trust" "$@"' \
  _ "$INTERNAL" "$HOST" ${args[@]+"${args[@]}"} >>"$LOG" 2>&1 < /dev/null &

# echo "==> Waiting for dsh on 127.0.0.1:$INTERNAL"
ok=
for _ in $(seq 1 60); do
  if (exec 3<>"/dev/tcp/127.0.0.1/$INTERNAL") 2>/dev/null; then ok=1; break; fi
  if [[ -z $(find_pids "$DSH_PATTERN") ]]; then
    echo "dsh exited before listening; see $LOG" >&2; exit 1
  fi
  sleep 1
done
[[ -n $ok ]] || { echo "dsh did not listen within 60s; see $LOG" >&2; exit 1; }

echo "==> Relaying 0.0.0.0:$PUBLIC -> 127.0.0.1:$INTERNAL (Basic auth user: $BASIC_USER)"
export DSH_RELAY_PORT="$PUBLIC" DSH_UPSTREAM_PORT="$INTERNAL"
# The /dsh redirect is opt-in (--no-token): without DSH_TOKEN_FILE the relay
# proxies /dsh upstream verbatim, exactly like every other path.
if (( NO_TOKEN )); then export DSH_TOKEN_FILE="$PWD/dsh-token-url"; fi
[[ -n $TLS_CERT ]] && export DSH_TLS_CERT="$TLS_CERT"
[[ -n $TLS_KEY ]]  && export DSH_TLS_KEY="$TLS_KEY"
setsid node -e "$RELAY_JS" "$RELAY_MARKER" >>"$LOG" 2>&1 < <(printf '%s' "$BASIC_USER:$BASIC_PASS") &
sleep 1
if [[ -z $(find_pids "$RELAY_PATTERN") ]]; then
  echo "relay failed to start; see $LOG" >&2
  stop_by dsh "$DSH_PATTERN"
  exit 1
fi

# grep exits 1 while the token is not in the log yet; under pipefail that would
# abort the script before the URL is reported, so neutralise it here.
TOKEN=""
for _ in $(seq 1 20); do
  TOKEN=$(grep -o 'token=[^ ]*' "$LOG" | tail -1 || true)
  [[ -n $TOKEN ]] && break
  sleep 0.5
done
URL="$SCHEME://$HOST:$PUBLIC/?$TOKEN"
# With --no-token the relay reads this file per request and redirects /dsh to
# it, so the token URL itself never has to be typed. Without the flag nothing
# is written and the URL above is the only way in.
if (( NO_TOKEN )) && [[ -n $TOKEN ]]; then
  # Subshell umask so the file is 600 at creation (no world-readable window),
  # and never write through a symlink planted in the gap since the rm above.
  [[ -L $PWD/dsh-token-url ]] && rm -f "$PWD/dsh-token-url"
  ( umask 077; printf '%s\n' "$URL" > "$PWD/dsh-token-url" )
  echo "==> Visit $SCHEME://$HOST:$PUBLIC/dsh to automatically obtain the token"
  echo "    (Give the harness a minute to fully start)"
elif (( NO_TOKEN )); then
  echo "warning: no token in the log yet; /dsh will not redirect until one appears (see $LOG)" >&2
fi
echo "==> Open from the host: $URL"
echo "==> Detached. Log: $LOG"
echo "==> Stop:  $0 stop"
