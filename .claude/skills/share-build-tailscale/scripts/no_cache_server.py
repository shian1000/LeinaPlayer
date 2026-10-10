"""Static file server that tells clients never to cache responses.

The shared APK keeps the same URL across builds, so a cached copy in the
phone's browser would silently install an old build.
Usage: no_cache_server.py <port> <bind_address> <directory>
"""

import functools
import http.server
import sys


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    port, bind, directory = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    handler = functools.partial(NoCacheHandler, directory=directory)
    with http.server.ThreadingHTTPServer((bind, port), handler) as httpd:
        print(f"Serving {directory} on http://{bind}:{port}/", flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
