#!/usr/bin/env bash
# Start the DeepSeek Harness web UI detached: dsh listens on 127.0.0.1:PORT+1,
# a relay owns 0.0.0.0:PORT (Basic auth gate, byte-verbatim pipe). dsh is
# launched with --trusted-host HOST so the browser's real Host/Origin pass the
# /api fence. No pidfiles: processes are found by cmdline and stopped by
# process group. dsh.log is the only state written.
#
# Usage: ./run-deepseek-harness.sh -u USER (-p PASS | --pass-stdin) --host-ip ADDR [--port N] [dsh web args]
#        ./run-deepseek-harness.sh stop
set -euo pipefail

PUBLIC=3080           # relay port on 0.0.0.0; dsh uses PUBLIC+1 on loopback
BASIC_USER=""; BASIC_PASS=""; HOST=""
TLS_CERT=""; TLS_KEY=""; TLS_ENABLED=1   # TLS on by default; cert auto-generated

usage() {
  cat >&2 <<'EOF'
usage: ./run-deepseek-harness.sh -u USER (-p PASS | --pass-stdin) --host-ip ADDR [--port N] [dsh web args]
       ./run-deepseek-harness.sh stop
  -u, --user USER    Basic auth user
  -p, --pass PASS    Basic auth password
      --pass-stdin   read the password from stdin (preferred in login shells)
  -i, --host-ip ADDR IP/hostname clients reach this box on (IPv4 or hostname)
      --port N       relay port (default 3080); dsh uses N+1 on loopback
      --tls-cert FILE TLS cert PEM (default $PWD/tls-cert.pem; self-signed if missing)
      --tls-key FILE  TLS key PEM  (default $PWD/tls-key.pem; generated if missing)
      --no-tls        serve plain HTTP instead of TLS (default is TLS)
  -h, --help         show this help
  Run needs: -u USER, a password (-p PASS or --pass-stdin), and -i/--host-ip ADDR.
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
    --pass-stdin)   BASIC_PASS=$(head -n 1); shift ;;
    -i|--host-ip)   [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 1; }
                    HOST=$2; shift 2 ;;
    --port)         [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 1; }
                    PUBLIC=$2; port_given=1; shift 2 ;;
    --tls-cert)     [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 1; }
                    TLS_CERT=$2; shift 2 ;;
    --tls-key)      [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 1; }
                    TLS_KEY=$2; shift 2 ;;
    --no-tls)       TLS_ENABLED=0; shift ;;
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
  exit 0
fi

[[ -n $BASIC_USER ]] || { echo "missing --user (see: $0 --help)" >&2; exit 1; }
[[ -n $BASIC_PASS ]] || { echo "missing --pass / --pass-stdin (see: $0 --help)" >&2; exit 1; }
[[ -n $HOST ]] || { echo "missing --host-ip (see: $0 --help)" >&2; exit 1; }

export PATH="$HOME/.local/node/bin:$PATH"
export NODE_USE_ENV_PROXY=1    # node's fetch honors proxy env vars
command -v node >/dev/null 2>&1 || { echo "node not found -- run ./install-deepseek-harness.sh first" >&2; exit 1; }

cd "$(dirname "$0")"
LOG="$PWD/dsh.log"

# TLS: default on. Resolve cert/key paths, generating a self-signed cert here
# if none exists (openssl required then). SCHEME drives the printed URL.
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
          const u = net.connect(up, "127.0.0.1");
          u.on("error", () => s.destroy());
          s.on("error", () => u.destroy());
          u.on("connect", () => { u.write(buf); s.pipe(u); u.pipe(s); });
        } else {
          s.end("HTTP/1.1 401 Unauthorized\r\n" +
                "WWW-Authenticate: Basic realm=\"dsh\"\r\n" +
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
echo "==> Starting dsh web on 127.0.0.1:$INTERNAL (log: $LOG)"
setsid bash -c 'internal=$1; trust=$2; shift 2; \
  exec dsh web --no-open --port "$internal" --trusted-host "$trust" "$@"' \
  _ "$INTERNAL" "$HOST" ${args[@]+"${args[@]}"} >>"$LOG" 2>&1 < /dev/null &

echo "==> Waiting for dsh on 127.0.0.1:$INTERNAL"
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
[[ -n $TLS_CERT ]] && export DSH_TLS_CERT="$TLS_CERT"
[[ -n $TLS_KEY ]]  && export DSH_TLS_KEY="$TLS_KEY"
setsid node -e "$RELAY_JS" "$RELAY_MARKER" >>"$LOG" 2>&1 < <(printf '%s' "$BASIC_USER:$BASIC_PASS") &
sleep 1
if [[ -z $(find_pids "$RELAY_PATTERN") ]]; then
  echo "relay failed to start; see $LOG" >&2
  stop_by dsh "$DSH_PATTERN"
  exit 1
fi

for _ in $(seq 1 20); do
  TOKEN=$(grep -o 'token=[^ ]*' "$LOG" | tail -1)
  [[ -n $TOKEN ]] && break
  sleep 0.5
done
echo "==> Open from the host: $SCHEME://$HOST:$PUBLIC/?$TOKEN"
echo "==> Detached. Log: $LOG"
echo "==> Stop:  $0 stop"
