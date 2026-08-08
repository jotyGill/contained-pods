#!/usr/bin/env python3
"""Simple Python server for Squid log viewer.

Why this exists
================
logviewer.html is pure client-side. The *browser* opens the log file itself and could not read files owned by other users (squid's UID). Podman
proxy containers are writing logs owned by a different UID. Believe me I have tried differnt solutions... this is simple and works.

This server is supposed to run as root using sudo and it hands the log files to the browser.

Features
========
- Serves logviewer.html itself at /
- GET /api/containers  -> auto-discovers containers by locating
                          */proxy/logs/squid-access.log under --root and
                          returns {"containers":[{"name","path","size"},...]}
- GET /raw/<relpath>   -> serves a discovered log's raw bytes.
- CORS headers on every response, so a file:// page can still fetch.
- Path-traversal guard: /raw/... is confined to --root.

Usage
=====
    # run as root/sudo so it can read podman-owned logs
    sudo python3 logserver.py --root /path/to/contained-dockers --port 8090

    # defaults: --root=current dir --host=127.0.0.1 --port=8090
    sudo python3 logserver.py

Then open http://127.0.0.1:8090/ and pick a container from the dropdown.
"""
import argparse
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

CORS = "*"  # allow a file:// page or any origin to fetch
MIME_CSS = "text/css; charset=utf-8"
MIME_HTML = "text/html; charset=utf-8"
MIME_JS = "text/javascript; charset=utf-8"
MIME_JSON = "application/json; charset=utf-8"
MIME_TXT = "text/plain; charset=utf-8"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

EXT_MIME = {
    ".html": MIME_HTML,
    ".css": MIME_CSS,
    ".js": MIME_JS,
    ".json": MIME_JSON,
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
}


def _container_name(log_relpath):
    """Name of the container for a log at ``.../<name>/proxy/logs/squid-access.log``.

    The container is the path segment immediately before ``proxy``. Returns the
    full container path segment (e.g. ``dockers/agents`` -> ``agents``).
    """
    marker = "/proxy/logs/"
    idx = log_relpath.find(marker)
    if idx < 0:
        return os.path.basename(os.path.dirname(os.path.dirname(log_relpath)))
    container_dir = log_relpath[:idx]  # e.g. "dockers/agents"
    return os.path.dirname(container_dir) not in ("",) and os.path.basename(container_dir) or container_dir


def collect_containers(root):
    """Scan ``root`` for */proxy/logs/squid-access.log and group by container.

    Returns a list of dicts: {"name","path","size"} where ``path`` is relative
    to ``root`` and ``name`` is derived from the container dir name. If several
    matches share the same container name (e.g. a stray copy under a git/work
    tree), the shallowest one wins so the chooser stays clean.
    """
    found = {}  # name -> (depth, relpath, size)
    for dirpath, _dirs, files in os.walk(root):
        if os.path.basename(dirpath) != "logs":
            continue
        if "squid-access.log" not in files:
            continue
        log_path = os.path.join(dirpath, "squid-access.log")
        rel = os.path.relpath(log_path, root)
        name = _container_name(rel)
        try:
            size = os.path.getsize(log_path)
        except OSError:
            size = -1
        depth = rel.count(os.sep)
        prev = found.get(name)
        if prev is None or depth < prev[0]:
            found[name] = (depth, rel, size)
    return [{"name": n, "path": p, "size": s} for n, (_, p, s) in found.items()]


def safe_join(root, relpath):
    """Return an absolute path under ``root`` for ``relpath``, or None if the
    resolved path escapes ``root`` (path-traversal guard)."""
    root_abs = os.path.abspath(root)
    joined = os.path.abspath(os.path.join(root_abs, relpath))
    if os.path.commonpath([root_abs, joined]) != root_abs:
        return None
    return joined


class Handler(BaseHTTPRequestHandler):
    # Silence per-request logs (a lot of lines when tailing big logs).
    def log_message(self, fmt, *args):
        pass

    def _headers(self, content_type, length):
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Access-Control-Allow-Origin", CORS)
        self.send_header("Cache-Control", "no-cache")

    def _send_bytes(self, body, content_type, code=200):
        self.send_response(code)
        self._headers(content_type, len(body))
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, obj, code=200):
        self._send_bytes(json.dumps(obj).encode("utf-8"), MIME_JSON, code)

    def _serve_static(self, path):
        # Serve files from the script directory (e.g. logviewer.html, and any
        # sibling .css/.js). Confined to SCRIPT_DIR.
        rel = os.path.normpath(path.lstrip("/"))
        if rel == ".":
            rel = "logviewer.html"
        full = safe_join(SCRIPT_DIR, rel)
        if not full or not os.path.isfile(full):
            self._send_bytes(b"404 Not Found\n", MIME_TXT, 404)
            return
        ext = os.path.splitext(full)[1]
        mime = EXT_MIME.get(ext, MIME_TXT)
        try:
            with open(full, "rb") as f:
                self._send_bytes(f.read(), mime)
        except OSError as e:
            self._send_bytes(f"error: {e}\n".encode(), MIME_TXT, 403)

    def do_GET(self):
        parsed = urlsplit(self.path)
        path = unquote(parsed.path)

        if path == "/" or path == "/logviewer.html":
            self._serve_static("/logviewer.html")
            return

        if path == "/api/containers":
            containers = collect_containers(self.server.root)
            self._send_json({"containers": containers})
            return

        if path.startswith("/raw/"):
            rel = path[len("/raw/"):]
            full = safe_join(self.server.root, rel)
            if not full:
                self._send_bytes(b"Forbidden: path escapes base directory\n",
                                 MIME_TXT, 403)
                return
            try:
                with open(full, "rb") as f:
                    self._send_bytes(f.read(), MIME_TXT)
            except OSError as e:
                self._send_bytes(f"error: {e}\n".encode(), MIME_TXT, 403)
            return

        self._send_bytes(b"404 Not Found\n", MIME_TXT, 404)

    def do_OPTIONS(self):
        # CORS preflight — allow the browser's fetch() from any origin.
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", CORS)
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()


def main():
    p = argparse.ArgumentParser(
        description="Serve a multi-container Squid log viewer and its logs.")
    p.add_argument("--root", default=os.getcwd(),
                   help="Base directory to scan for containers' logs (default: cwd).")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8090)
    a = p.parse_args()

    httpd = ThreadingHTTPServer((a.host, a.port), Handler)
    httpd.root = a.root
    print(f"Serving logviewer + logs from {a.root}")
    print(f"  ->  http://{a.host}:{a.port}/")
    try:
        containers = collect_containers(a.root)
    except OSError as e:
        print(f"Warning: could not scan {a.root!r}: {e}", file=sys.stderr)
        containers = []
    if containers:
        print(f"Discovered {len(containers)} container(s):")
        for c in containers:
            print(f"  - {c['name']}: {c['path']} ({c['size']} bytes)")
    else:
        print("No *\u2215proxy/logs/squid-access.log files found under the root.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
