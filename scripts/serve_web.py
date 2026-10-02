"""Serve a Flutter release build locally with the same routing as Vercel.

Usage: python serve_web.py --directory <build/web> --port 8080

Paths that are not files fall back to index.html, matching the vercel.json
rewrite, so deep links such as /app load the application. The server binds to
127.0.0.1 only and is for local staging runs, not deployment.
"""

from __future__ import annotations

import argparse
import functools
import http.server
from pathlib import Path

SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}
class FlutterWebHandler(http.server.SimpleHTTPRequestHandler):
    # Fixed types: Windows can map .js to text/plain in the registry, which a
    # browser rejects under nosniff.
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".json": "application/json",
        ".wasm": "application/wasm",
    }

    def send_head(self):
        path = self.path.split("?", 1)[0].split("#", 1)[0]
        if not Path(self.translate_path(path)).is_file():
            self.path = "/index.html"
        return super().send_head()

    def end_headers(self):
        for name, value in SECURITY_HEADERS.items():
            self.send_header(name, value)
        # Bundle names are not fingerprinted and every launch rebuilds them, so
        # always revalidate; a 304 is cheap on localhost.
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, format, *args):
        # Keep request logs out of the console; errors still reach stderr.
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--port", required=True, type=int)
    arguments = parser.parse_args()
    directory = arguments.directory.resolve()
    if not (directory / "index.html").is_file():
        raise SystemExit(f"No Flutter web build found in {directory}")
    handler = functools.partial(FlutterWebHandler, directory=str(directory))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", arguments.port), handler)
    print(f"Serving Flutter release build at http://127.0.0.1:{arguments.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
