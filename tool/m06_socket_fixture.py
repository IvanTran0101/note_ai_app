"""Loopback-only AppSync protocol fixture. Synthetic identities, no AWS claim."""
import base64
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from websockets.sync.server import serve

CLIENTS = {}
LOCK = threading.RLock()
ACTORS = {"m06-owner-20261002", "m06-editor-20261002"}
TOKEN_MARKER = "fixture"


def actor_of(token):
    parts = token.split(".")
    if len(parts) != 3 or parts[2] != TOKEN_MARKER:
        raise ValueError("Synthetic credential required")
    claims = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
    actor = claims.get("sub")
    if actor not in ACTORS or claims.get("token_use") != "id" or claims.get("exp", 0) <= time.time():
        raise ValueError("Synthetic credential required")
    return actor


def websocket(connection):
    actor = None
    try:
        protocols = connection.request.headers["Sec-WebSocket-Protocol"].split(",")
        encoded = next(x.strip()[7:] for x in protocols if x.strip().startswith("header-"))
        header = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
        actor = actor_of(header["Authorization"])
        for raw in connection:
            frame = json.loads(raw)
            if frame.get("type") == "connection_init":
                connection.send(json.dumps({"type": "connection_ack", "connectionTimeoutMs": 300000}))
            elif frame.get("type") == "subscribe":
                if frame.get("channel") != "/notes/" + actor or actor_of(frame["authorization"]["Authorization"]) != actor:
                    connection.send(json.dumps({"type": "subscribe_error", "id": frame.get("id")}))
                    continue
                with LOCK:
                    CLIENTS[actor] = (connection, frame["id"])
                connection.send(json.dumps({"type": "subscribe_success", "id": frame["id"]}))
            elif frame.get("type") == "publish":
                connection.send(json.dumps({"type": "publish_error", "id": frame.get("id")}))
    except Exception:
        pass
    finally:
        with LOCK:
            if actor in CLIENTS and CLIENTS[actor][0] is connection:
                del CLIENTS[actor]


class Control(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        try:
            row = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            actor = row["actor"]
            if actor not in ACTORS:
                raise ValueError()
            with LOCK:
                current = CLIENTS.get(actor)
            if current:
                connection, subscription = current
                if self.path == "/disconnect":
                    connection.close()
                elif self.path == "/publish":
                    connection.send(json.dumps({"type": "data", "id": subscription,
                                                "event": [json.dumps(row["signal"])]}))
                else:
                    raise ValueError()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"failed":[]}')
        except Exception:
            self.send_response(503)
            self.end_headers()


def keepalive():
    while True:
        time.sleep(1)
        with LOCK:
            current = list(CLIENTS.values())
        for connection, _ in current:
            try:
                connection.send('{"type":"ka"}')
            except Exception:
                pass


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-dev", action="store_true")
    options = parser.parse_args()
    socket_port, control_port = 8787, 8788
    if options.local_dev:
        ACTORS = {"m06-dev-owner", "m06-dev-recipient"}
        socket_port, control_port = 8797, 8798
        TOKEN_MARKER = "local-dev"
    threading.Thread(target=ThreadingHTTPServer(("127.0.0.1", control_port), Control).serve_forever,
                     daemon=True).start()
    threading.Thread(target=keepalive, daemon=True).start()
    print(f"M06 synthetic socket fixture ready: {socket_port}/{control_port}", flush=True)
    with serve(websocket, "127.0.0.1", socket_port, subprotocols=["aws-appsync-event-ws"]) as server:
        server.serve_forever()
