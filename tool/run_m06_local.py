"""Run the actual NoteFlow UI with two local demo users; no AWS credentials."""
import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
PORTS = (8796, 8797, 8798)


def occupied(port):
    with socket.socket() as connection:
        connection.settimeout(0.2)
        return connection.connect_ex(("127.0.0.1", port)) == 0


def ready():
    try:
        with urlopen("http://127.0.0.1:8796/dev/health", timeout=1) as response:
            return json.load(response) == {"kind": "m06-local-dev", "version": 1} and all(
                occupied(port) for port in PORTS)
    except Exception:
        return False


def start_services(node, output, children, logs):
    hidden = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
    commands = (("socket", [sys.executable, "tool/m06_socket_fixture.py", "--local-dev"]),
                ("server", [node, "--import", "tsx", "amplify/dev/local_server.ts"]))
    for name, command in commands:
        log = (output / (name + ".log")).open("w", encoding="utf-8")
        logs.append(log)
        children.append(subprocess.Popen(command, stdout=log, stderr=log, creationflags=hidden))
    deadline = time.monotonic() + 40
    while not ready():
        if any(child.poll() is not None for child in children) or time.monotonic() > deadline:
            raise RuntimeError("Local services failed; inspect output/m06-local/server.log and socket.log")
        time.sleep(0.25)


def run_flutter(args, flutter):
    command = [flutter, "run", "-d", args.device, "-t", "lib/main_dev.dart", "--no-pub",
               "--dart-define=NOTEFLOW_AUTH_MODE=local", f"--dart-define=M06_DEV_USER={args.user}",
               "--web-hostname=127.0.0.1", "--web-port=8776"]
    return subprocess.call(command)


def stop_services(children, logs):
    for child in reversed(children):
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    for log in logs:
        log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", choices=("chrome", "web-server"), default="chrome")
    parser.add_argument("--user", choices=("owner", "recipient"), default="owner")
    parser.add_argument("--serve-only", action="store_true", help="Start local services without Flutter")
    args = parser.parse_args()
    os.chdir(ROOT)
    node = shutil.which("node")
    flutter = shutil.which("flutter")
    if not node or (not args.serve_only and not flutter):
        parser.error("Node.js and Flutter must be available on PATH")
    tsx = ROOT / "node_modules/tsx/dist/cli.mjs"
    if not tsx.is_file():
        parser.error("Run npm ci first to restore the existing backend dependencies")
    if any(occupied(port) for port in PORTS):
        parser.error("Local dev ports8796/8797/8798 are already in use; stop that local dev run first")
    output = ROOT / "output/m06-local"
    output.mkdir(parents=True, exist_ok=True)
    children, logs = [], []
    try:
        start_services(node, output, children, logs)
        print("Local Share is ready. Fixed demo users (no login/password):", flush=True)
        print("Owner:     http://127.0.0.1:8776/?devUser=owner", flush=True)
        print("Recipient: http://127.0.0.1:8776/?devUser=recipient", flush=True)
        print("Share to recipient@example.invalid. Ctrl+C stops only this run's services.", flush=True)
        if args.serve_only:
            while all(child.poll() is None for child in children):
                time.sleep(0.5)
            raise RuntimeError("A local service stopped unexpectedly")
        return run_flutter(args, flutter)
    except KeyboardInterrupt:
        return 0
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1
    finally:
        stop_services(children, logs)


if __name__ == "__main__":
    sys.exit(main())
