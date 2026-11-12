"""Prepare public Flutter config; scope private AWS auth to a backend child only."""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ("NOTEFLOW_SYNC_API", "NOTEFLOW_EVENT_HTTP", "NOTEFLOW_EVENT_SOCKET")
KEYS = ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN")
ALLOWED = {*PUBLIC, *KEYS, "NOTEFLOW_AUTH_MODE", "NOTEFLOW_AMPLIFY_OUTPUTS_FILE",
           "AWS_PROFILE", "AWS_REGION", "NOTEFLOW_LABELS_ENABLED"}
SECRET_FIELDS = {"awsaccesskeyid", "awssecretaccesskey", "awssessiontoken",
                 "accesskeyid", "secretaccesskey", "sessiontoken", "password",
                 "token", "authorization", "unlockgrant", "privatekey", "apikey"}
SECRET_SUFFIXES = ("secret", "secretkey", "apikey", "privatekey", "password",
                   "accesstoken", "refreshtoken", "idtoken", "sessiontoken", "unlockgrant")


def read_env(path):
    values = {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if not separator or not re.fullmatch(r"[A-Z][A-Z0-9_]*", key) or key not in ALLOWED:
            raise ValueError(f"Unsupported setting at line {line_number}")
        if key in values:
            raise ValueError(f"Duplicate setting at line {line_number}")
        if value.startswith(("'", '"')):
            if len(value) < 2 or value[-1] != value[0]:
                raise ValueError(f"Unclosed quote at line {line_number}")
            value = value[1:-1]
        values[key] = value
    return values


def validate_auth(values):
    profile = values.get("AWS_PROFILE", "")
    access, secret, token = (values.get(key, "") for key in KEYS)
    if bool(access) != bool(secret) or (token and not access):
        raise ValueError("AWS temporary credentials require an access/secret pair")
    if profile and access:
        raise ValueError("Choose AWS_PROFILE or temporary credentials, not both")


def reject_private_fields(value):
    if isinstance(value, dict):
        for key, item in value.items():
            name = re.sub(r"[^a-z0-9]", "", key.lower())
            if name in SECRET_FIELDS or name.endswith(SECRET_SUFFIXES):
                raise ValueError("Private credential field found in public outputs")
            reject_private_fields(item)
    elif isinstance(value, list):
        for item in value:
            reject_private_fields(item)


def endpoint(value, scheme):
    parsed = urlsplit(value)
    if (parsed.scheme != scheme or not parsed.hostname or parsed.username is not None
            or parsed.password is not None or parsed.query or parsed.fragment):
        raise ValueError(f"Public endpoint requires {scheme} without credentials/query/fragment")
    return value


def public_defines(values, env_directory):
    mode = values.get("NOTEFLOW_AUTH_MODE", "local")
    if mode not in ("local", "cognito"):
        raise ValueError("NOTEFLOW_AUTH_MODE must be local or cognito")
    result = {"NOTEFLOW_AUTH_MODE": mode}
    labels = values.get("NOTEFLOW_LABELS_ENABLED", "false")
    if labels not in ("true", "false"):
        raise ValueError("NOTEFLOW_LABELS_ENABLED must be true or false")
    if labels == "true":
        result["NOTEFLOW_LABELS_ENABLED"] = "true"
    if mode == "local":
        return result
    source = values.get("NOTEFLOW_AMPLIFY_OUTPUTS_FILE", "")
    if not source:
        raise ValueError("Cognito mode requires the intended dev deployment's public outputs file")
    outputs = json.loads((env_directory / source).read_text(encoding="utf-8-sig"))
    reject_private_fields(outputs)
    if not isinstance(outputs, dict) or not isinstance(outputs.get("auth"), dict):
        raise ValueError("Public Amplify outputs must contain auth configuration")
    auth = outputs["auth"]
    required = ("aws_region", "user_pool_id", "user_pool_client_id")
    if any(not isinstance(auth.get(key), str) or not auth[key].strip() for key in required):
        raise ValueError("Public outputs require Cognito region, pool and app client")
    custom = outputs.get("custom", {})
    if not isinstance(custom, dict):
        raise ValueError("Public outputs custom must be an object")
    fields = ("syncApiEndpoint", "eventHttpEndpoint", "eventSocketEndpoint")
    for key, field, scheme in zip(PUBLIC, fields, ("https", "https", "wss")):
        value = values.get(key, "") or custom.get(field, "")
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"M06 dev configuration requires {key} or custom.{field}")
        result[key] = endpoint(value.strip(), scheme)
    result["NOTEFLOW_AMPLIFY_OUTPUTS"] = json.dumps(outputs, separators=(",", ":"))
    return result


def backend_environment(values, inherited):
    validate_auth(values)
    result = dict(inherited)
    if values.get("AWS_PROFILE"):
        for key in (*KEYS, "AWS_DEFAULT_PROFILE"):
            result.pop(key, None)
        result["AWS_PROFILE"] = values["AWS_PROFILE"]
    elif values.get("AWS_ACCESS_KEY_ID"):
        for key in (*KEYS, "AWS_PROFILE", "AWS_DEFAULT_PROFILE"):
            result.pop(key, None)
        result.update({key: values[key] for key in KEYS if values.get(key)})
    if values.get("AWS_REGION"):
        result["AWS_REGION"] = values["AWS_REGION"]
        result["AWS_DEFAULT_REGION"] = values["AWS_REGION"]
    return result


def output_path(value):
    target = (ROOT / value).resolve()
    ignored_output = (ROOT / "output").resolve()
    if not target.is_relative_to(ignored_output) or target == ignored_output:
        raise ValueError("Generated build configuration must stay under ignored output/")
    return target


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", type=Path, default=ROOT / ".env")
    sub = parser.add_subparsers(dest="action", required=True)
    prepare = sub.add_parser("prepare", help="Write public-only Dart defines; no AWS call")
    prepare.add_argument("--output", default="output/m06-dev/dart-defines.json")
    backend = sub.add_parser("backend", help="Run an explicit backend command with process-local AWS auth")
    backend.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    try:
        values = read_env(args.env.resolve())
        validate_auth(values)
        if args.action == "prepare":
            defines = public_defines(values, args.env.resolve().parent)
            target = output_path(args.output)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(defines, indent=2) + "\n", encoding="utf-8")
            print("Public build config prepared; private AWS credentials excluded.")
            return 0
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if not command:
            raise ValueError("Provide an explicit backend command after --")
        # No shell interpolation, global environment mutation or credential output.
        return subprocess.run(command, env=backend_environment(values, os.environ),
                              cwd=ROOT, check=False).returncode
    except (OSError, ValueError) as error:
        # Exception details may contain input values; print a safe class/message only.
        safe = str(error) if type(error) is ValueError else "Configuration file/command could not be read or run"
        print(f"Configuration error: {safe}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
