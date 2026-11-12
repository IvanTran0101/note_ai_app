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


def subscribe(actor, connection, subscription):
    with LOCK:
        CLIENTS.setdefault(actor, {})[connection] = subscription


def unsubscribe(actor, connection):
    with LOCK:
        clients = CLIENTS.get(actor, {})
        clients.pop(connection, None)
        if not clients:
            CLIENTS.pop(actor, None)


def clients_for(actor):
    with LOCK:
        return list(CLIENTS.get(actor, {}).items())


def publish(actor, signal):
    for connection, subscription in clients_for(actor):
        try:
            connection.send(json.dumps({"type": "data", "id": subscription,
                                        "event": [json.dumps(signal)]}))
        except Exception:
            unsubscribe(actor, connection)


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
                subscribe(actor, connection, frame["id"])
                connection.send(json.dumps({"type": "subscribe_success", "id": frame["id"]}))
            elif frame.get("type") == "unsubscribe":
                if dict(clients_for(actor)).get(connection) == frame.get("id"):
                    unsubscribe(actor, connection)
            elif frame.get("type") == "publish":
                connection.send(json.dumps({"type": "publish_error", "id": frame.get("id")}))
    except Exception:
        pass
    finally:
        unsubscribe(actor, connection)


class Control(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        try:
            row = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            actor = row["actor"]
            if actor not in ACTORS:
                raise ValueError()
            if self.path == "/disconnect":
                for connection, _ in clients_for(actor):
                    connection.close()
            elif self.path == "/publish":
                publish(actor, row["signal"])
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
            current = [(connection, actor) for actor, clients in CLIENTS.items()
                       for connection in clients]
        for connection, actor in current:
            try:
                connection.send('{"type":"ka"}')
            except Exception:
                unsubscribe(actor, connection)


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
