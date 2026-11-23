#!/usr/bin/env python3
"""Serve a built Flutter web app on loopback HTTPS, with no access logs."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import ssl


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', default='build/web')
    parser.add_argument('--cert', required=True)
    parser.add_argument('--key', required=True)
    parser.add_argument('--port', type=int, default=8782)
    args = parser.parse_args()
    directory = Path(args.directory).resolve()
    if not (directory / 'flutter_bootstrap.js').is_file():
        parser.error('directory must contain the built Flutter web app')
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(args.cert, args.key)
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Handler, directory=str(directory)))
    server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f'https://localhost:{args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
