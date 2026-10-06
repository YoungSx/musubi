#!/usr/bin/env python3
"""HTTP development server for Musubi Godot Web export.

Serves build/web with cross-origin isolation headers (COOP/COEP)
and proper WebAssembly MIME types, bound to all network interfaces
for local (loopback) and Tailscale remote access.
"""

import argparse
import http.server
import mimetypes
import os
import socketserver
import sys

DEFAULT_PORT = 8080
DIRECTORY = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "build", "web"))

# Ensure proper MIME types for Godot Web export
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("application/octet-stream", ".pck")


class GodotWebHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """Custom HTTP handler setting headers for Godot 4 Web builds."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self) -> None:
        # Cross-origin isolation required for SharedArrayBuffer and high-precision timers
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # Disable caching during development to reflect rebuilds immediately
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, format: str, *args) -> None:
        sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve Musubi Godot Web export.")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port to bind (default: 8080)")
    parser.add_argument("--bind", type=str, default="0.0.0.0", help="Address to bind (default: 0.0.0.0)")
    args = parser.parse_args()

    if not os.path.exists(DIRECTORY):
        print(f"Error: Build directory not found: {DIRECTORY}", file=sys.stderr)
        print("Please build the web export first: godot --headless --export-release 'Web' build/web/index.html", file=sys.stderr)
        sys.exit(1)

    index_path = os.path.join(DIRECTORY, "index.html")
    if not os.path.exists(index_path):
        print(f"Warning: {index_path} does not exist yet. Please export Web preset.", file=sys.stderr)

    with ThreadedHTTPServer((args.bind, args.port), GodotWebHTTPRequestHandler) as httpd:
        print(f"Serving {DIRECTORY}")
        print(f"Listening on {args.bind}:{args.port}")
        print("Available access endpoints:")
        print(f"  Loopback:   http://localhost:{args.port}/ or http://127.0.0.1:{args.port}/")
        print(f"  Tailscale:  http://100.88.85.12:{args.port}/")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server.")
            httpd.shutdown()


if __name__ == "__main__":
    main()
