#!/usr/bin/env python3
"""Offline gate and direct-upload zip prep for the NoteFlow static web bundle.

The gate refuses known private/debug artifacts and obvious secret shapes in the
Flutter web build (default ``<root>/build/web``): recognized credential, corpus,
tokenizer and raw-note filenames plus a small set of debug/mock and
live-credential byte patterns.  This is a targeted provenance check, not a
comprehensive secret-absence proof: a release build still needs its own build
provenance and a separate secret audit.  On success it can write a
Wrangler-uploadable zip plus a manifest outside the public artifact root, and it
publishes only bytes that were pattern-scanned and hashed in the same pass.

Stdlib only.  It never contacts Cloudflare, Wrangler, AWS or any provider, and
it never stores, logs or prints the contents it matches.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

GATE_VERSION = "phase5.4-web-hosting-gate.v1"
# Cloudflare Workers Free static-asset limits, verified against the official
# platform limits page (2026): 20000 files per version, 25 MiB per file.
MAX_FILES = 20_000
MAX_FILE_BYTES = 25 * 1024 * 1024  # 26214400 bytes

REQUIRED_FILES = ("index.html", "main.dart.js", "flutter_bootstrap.js")
HEADERS_NAME = "_headers"
DEFAULT_BUILD_REL = ("build", "web")
APPROVED_HEADERS_REL = ("web", HEADERS_NAME)
DEFAULT_OUTPUT_REL = ("output", "rag", "phase5-implementation", "web-hosting")
ZIP_NAME = "noteflow-staging.zip"
MANIFEST_NAME = "noteflow-staging.manifest.json"

# Flutter writes this hidden build marker next to index.html.  It is not part of
# the served app, so it is excluded from the bundle instead of shipped.
BENIGN_HIDDEN_FILES = frozenset({".last_build_id"})

_READ_CHUNK = 1024 * 1024
_PATTERN_OVERLAP = 64

# Debug/mock builds must never reach staging; matched text is never reported.
_DEBUG_PATTERNS = (
    ("DEBUG_MOCK_MARKER", re.compile(rb"rag-mock\.invalid|OFFLINE RAG MOCK|main_rag_mock")),
)
# Obvious live credential shapes only; public Cognito ids and ``access_token``
# identifier names must stay allowed.
_SECRET_PATTERNS = (
    ("SECRET_AWS_ACCESS_KEY", re.compile(rb"(?:AKIA|ASIA)[0-9A-Z]{16}")),
    ("SECRET_SK_TOKEN", re.compile(rb"sk-[A-Za-z0-9_-]{20,}")),
    ("SECRET_PRIVATE_KEY", re.compile(rb"-----BEGIN [A-Z0-9 ]*PRIVATE KEY")),
)
_CONTENT_PATTERNS = _DEBUG_PATTERNS + _SECRET_PATTERNS

_PRIVATE_KEY_EXTS = frozenset({".pem", ".key", ".p12", ".pfx", ".jks", ".keystore", ".ppk"})
_CREDENTIAL_NAMES = frozenset({
    "credentials", "credentials.json", "credentials.yml", "credentials.yaml",
    ".netrc", ".npmrc", ".git-credentials", ".pgpass",
    "google-services.json", "googleservice-info.plist",
    "id_rsa", "id_ed25519", "service-account.json",
})
_CORPUS_SEGMENTS = frozenset({"corpus", "bm25", "rag-corpus", "rag_corpus", "vector-index", "vector_index"})
_CORPUS_EXTS = frozenset({".gguf"})
_TOKENIZER_SEGMENTS = ("tokenizer", "sentencepiece")
_TOKENIZER_NAMES = frozenset({
    "vocab.json", "merges.txt", "special_tokens_map.json", "tokenizer.json",
    "tokenizer_config.json", "sentencepiece.model",
})
_RAW_NOTE_NAMES = frozenset({
    "notes.json", "note_cases.json", "query_cases.json", "ranking_cases.json",
    "wire_cases.json", "context_cases.json",
})


class GateError(Exception):
    """Closed gate failure.  ``path`` is a pathname; ``detail`` never has content."""

    def __init__(self, code: str, path: str = "", detail: str = "") -> None:
        self.code = code
        self.path = path
        self.detail = detail
        message = code if not path else f"{code}: {path}"
        super().__init__(message if not detail else f"{message} ({detail})")


@dataclass(frozen=True)
class ScannedFile:
    relative: str
    size: int
    sha256: str


@dataclass(frozen=True)
class ScanResult:
    directory: Path
    root: Path
    files: tuple
    excluded: tuple
    headers_action: str
    total_bytes: int


def repo_root() -> Path:
    """Repository root, derived from ``tool/rag/prepare_web_hosting.py``."""
    return Path(__file__).resolve().parents[2]


def sha256_file(path: Path, *, chunk: int = _READ_CHUNK) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(chunk), b""):
            digest.update(block)
    return digest.hexdigest()


def scan_stream(handle, patterns=_CONTENT_PATTERNS, *, max_bytes=None):
    """One pass over an open binary handle.

    Returns ``(flagged_code, sha256_hex, byte_count)`` computed from the exact
    same bytes, so a pattern verdict and a digest can never disagree about what
    was scanned.  ``max_bytes`` stops early once the stream is provably over a
    byte quota; the caller only needs the rejection, not a full digest.
    """
    digest = hashlib.sha256()
    total = 0
    tail = b""
    flagged = None
    while True:
        block = handle.read(_READ_CHUNK)
        if not block:
            break
        total += len(block)
        digest.update(block)
        window = tail + block
        if flagged is None:
            for code, regex in patterns:
                if regex.search(window):
                    flagged = code
                    break
        tail = window[-_PATTERN_OVERLAP:]
        if max_bytes is not None and total > max_bytes:
            break
    return flagged, digest.hexdigest(), total


def scan_content(path: Path, patterns=_CONTENT_PATTERNS):
    """Stream a file and return the first matching reason code, else ``None``."""
    with Path(path).open("rb") as handle:
        flagged, _digest, _size = scan_stream(handle, patterns)
    return flagged


def _is_within(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


def _is_env_name(lower_name: str) -> bool:
    return (lower_name == "env" or lower_name.startswith(".env")
            or lower_name.endswith(".env") or ".env." in lower_name)


def _reject_path(relative: Path) -> None:
    """Refuse a file by name/shape only; never opens it."""
    parts = relative.parts
    lower_parts = [part.lower() for part in parts]
    lower_name = relative.name.lower()
    extension = relative.suffix.lower()
    if extension in _PRIVATE_KEY_EXTS:
        raise GateError("PRIVATE_KEY_FILE", relative.as_posix())
    if lower_name in _CREDENTIAL_NAMES:
        raise GateError("CREDENTIAL_FILE", relative.as_posix())
    if _is_env_name(lower_name):
        raise GateError("ENV_FILE", relative.as_posix())
    if extension in _CORPUS_EXTS or any(seg in _CORPUS_SEGMENTS for seg in lower_parts):
        raise GateError("CORPUS_ASSET", relative.as_posix())
    if any(seg in _TOKENIZER_SEGMENTS for seg in lower_parts) or lower_name in _TOKENIZER_NAMES:
        raise GateError("TOKENIZER_ASSET", relative.as_posix())
    if lower_name in _RAW_NOTE_NAMES or "fixtures" in lower_parts:
        raise GateError("RAW_NOTE_FIXTURE", relative.as_posix())


def _enumerate(directory: Path):
    """Return (accepted relative paths, excluded pathnames).  Refuses symlinks."""
    accepted = []
    excluded = []
    for dirpath, dirnames, filenames in os.walk(directory, followlinks=False):
        base = Path(dirpath)
        for dirname in dirnames:
            relative = (base / dirname).relative_to(directory)
            if (base / dirname).is_symlink():
                raise GateError("SYMLINK", relative.as_posix())
            if dirname.startswith("."):
                raise GateError("HIDDEN_DIRECTORY", relative.as_posix())
        for filename in filenames:
            full = base / filename
            relative = full.relative_to(directory)
            if full.is_symlink():
                raise GateError("SYMLINK", relative.as_posix())
            _reject_path(relative)
            if filename.startswith("."):
                if filename in BENIGN_HIDDEN_FILES:
                    excluded.append(relative.as_posix())
                    continue
                raise GateError("HIDDEN_ENTRY", relative.as_posix())
            accepted.append(relative)
    accepted.sort(key=lambda path: path.as_posix())
    excluded.sort()
    return accepted, excluded


def _approved_headers(root: Path) -> bytes:
    source = Path(root).joinpath(*APPROVED_HEADERS_REL)
    if not source.is_file():
        raise GateError("HEADERS_SOURCE_MISSING", "/".join(APPROVED_HEADERS_REL))
    return source.read_bytes()


def _reconcile_headers(directory: Path, approved: bytes) -> str:
    """Copy approved headers only when absent; refuse an unexpected difference."""
    target = directory / HEADERS_NAME
    if target.is_symlink():
        raise GateError("SYMLINK", HEADERS_NAME)
    if not target.exists():
        target.write_bytes(approved)
        return "copied"
    if target.read_bytes() != approved:
        raise GateError("HEADERS_CHANGED", HEADERS_NAME, "artifact headers differ from approved web/_headers")
    return "present"


def scan_directory(directory, *, approved_headers=None, root=None,
                   max_files: int = MAX_FILES, max_file_bytes: int = MAX_FILE_BYTES) -> ScanResult:
    """Scan an artifact directory.  ``max_*`` are injectable for tests only."""
    root = Path(root) if root is not None else repo_root()
    directory = Path(directory)
    if directory.is_symlink():
        raise GateError("SYMLINK", str(directory))
    directory = directory.resolve()
    if not directory.is_dir():
        raise GateError("NOT_A_DIRECTORY", str(directory))
    if approved_headers is None:
        approved_headers = _approved_headers(root)
    headers_action = _reconcile_headers(directory, approved_headers)

    paths, excluded = _enumerate(directory)
    names = {path.as_posix() for path in paths}
    for required in (*REQUIRED_FILES, HEADERS_NAME):
        if required not in names:
            raise GateError("MISSING_REQUIRED", required)
    if len(paths) > max_files:
        raise GateError("TOO_MANY_FILES", "", f"count={len(paths)} limit={max_files}")

    scanned = []
    total_bytes = 0
    for relative in paths:
        full = directory / relative
        # One pass binds the pattern verdict, digest and byte count to the same
        # bytes; no second open can substitute different content in between.
        with full.open("rb") as handle:
            flagged, sha256, size = scan_stream(handle, max_bytes=max_file_bytes)
        if size > max_file_bytes:
            raise GateError("FILE_TOO_LARGE", relative.as_posix(),
                            f"size={size} limit={max_file_bytes}")
        if flagged is not None:
            raise GateError(flagged, relative.as_posix())
        scanned.append(ScannedFile(relative.as_posix(), size, sha256))
        total_bytes += size
    return ScanResult(directory, root, tuple(scanned), tuple(excluded), headers_action, total_bytes)


def _verify_unchanged(directory: Path, files) -> None:
    for item in files:
        full = directory / item.relative
        if full.is_symlink() or not full.is_file():
            raise GateError("CHANGED_SINCE_SCAN", item.relative)
        if full.stat().st_size != item.size or sha256_file(full) != item.sha256:
            raise GateError("CHANGED_SINCE_SCAN", item.relative)


def _manifest(scan: ScanResult, zip_path: Path) -> dict:
    return {
        "gateVersion": GATE_VERSION,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "sourceDirectory": _display_path(scan.directory, scan.root),
        "headersAction": scan.headers_action,
        "fileCount": len(scan.files),
        "totalBytes": scan.total_bytes,
        "excluded": list(scan.excluded),
        "limits": {"maxFiles": MAX_FILES, "maxFileBytes": MAX_FILE_BYTES},
        "zip": {
            "name": zip_path.name,
            "size": zip_path.stat().st_size,
            "sha256": sha256_file(zip_path),
        },
        "files": [{"path": item.relative, "size": item.size, "sha256": item.sha256}
                  for item in scan.files],
    }


class _HashingReader:
    """Wrap a reader and digest exactly the bytes handed to the zip writer."""

    def __init__(self, handle, expected: ScannedFile) -> None:
        self._handle = handle
        self._expected = expected
        self._digest = hashlib.sha256()
        self._size = 0

    def read(self, size: int = -1) -> bytes:
        block = self._handle.read(size)
        if block:
            self._digest.update(block)
            self._size += len(block)
        return block

    def verify(self) -> None:
        """Refuse if the copied bytes differ from the scanned ``ScannedFile``."""
        if (self._size != self._expected.size
                or self._digest.hexdigest() != self._expected.sha256):
            raise GateError("CHANGED_DURING_COPY", self._expected.relative)


def create_bundle(scan: ScanResult, output_dir, *, zip_name: str = ZIP_NAME,
                  manifest_name: str = MANIFEST_NAME):
    """Write the zip and manifest after re-hashing.  Nothing is written on failure."""
    output_dir = Path(output_dir)
    if _is_within(output_dir.resolve(), scan.directory):
        raise GateError("OUTPUT_INSIDE_ARTIFACT", str(output_dir))
    output_dir.mkdir(parents=True, exist_ok=True)
    zip_path = output_dir / zip_name
    manifest_path = output_dir / manifest_name

    _verify_unchanged(scan.directory, scan.files)
    partial = output_dir / (zip_name + ".part")
    if partial.exists():
        partial.unlink()
    try:
        with zipfile.ZipFile(partial, "w", zipfile.ZIP_DEFLATED) as archive:
            for item in scan.files:
                source = scan.directory / item.relative
                if source.is_symlink() or not source.is_file():
                    raise GateError("CHANGED_SINCE_SCAN", item.relative)
                with source.open("rb") as reader, archive.open(item.relative, "w") as writer:
                    checked = _HashingReader(reader, item)
                    shutil.copyfileobj(checked, writer, _READ_CHUNK)
                    # The manifest may only describe bytes the writer truly got.
                    checked.verify()
        os.replace(partial, zip_path)
        manifest_path.write_text(
            json.dumps(_manifest(scan, zip_path), indent=2, sort_keys=True) + "\n",
            encoding="utf-8")
    except BaseException:
        if partial.exists():
            partial.unlink()
        raise
    return zip_path, manifest_path


def resolve_cli_directory(raw, root) -> Path:
    """Confine a CLI ``--directory`` to ``<root>/build`` and refuse whole-project roots."""
    root = Path(root).resolve()
    candidate = Path(raw)
    if not candidate.is_absolute():
        candidate = root / candidate
    if candidate.is_symlink():
        raise GateError("SYMLINK", str(candidate))
    resolved = candidate.resolve()
    if resolved == root or resolved in root.parents:
        raise GateError("WHOLE_PROJECT", str(resolved))
    if not _is_within(resolved, root):
        raise GateError("OUTSIDE_REPO", str(resolved))
    if not _is_within(resolved, (root / "build").resolve()):
        raise GateError("OUTSIDE_BUILD", str(resolved))
    return resolved


def _display_path(path: Path, root: Path) -> str:
    path = Path(path)
    try:
        return path.relative_to(Path(root)).as_posix()
    except ValueError:
        return path.as_posix()


def _summary(status, scan=None, root=None, extras=None):
    payload = {"status": status, "gateVersion": GATE_VERSION}
    if scan is not None:
        payload.update({
            "directory": _display_path(scan.directory, root),
            "headersAction": scan.headers_action,
            "fileCount": len(scan.files),
            "totalBytes": scan.total_bytes,
            "excluded": list(scan.excluded),
        })
    if extras:
        payload.update(extras)
    return payload


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=repo_root(),
                        help="repository root (default: auto-detected)")
    parser.add_argument("--directory", type=Path, default=None,
                        help="artifact directory; confined to <root>/build")
    parser.add_argument("--output", type=Path, default=None,
                        help="zip/manifest directory (default: " + "/".join(DEFAULT_OUTPUT_REL) + ")")
    parser.add_argument("--zip", action="store_true", dest="make_zip",
                        help="write the direct-upload zip and manifest after a PASS")
    return parser


def main(argv=None) -> int:
    args = _parser().parse_args(argv)
    root = args.root.resolve()
    try:
        if args.directory is None:
            directory = (root.joinpath(*DEFAULT_BUILD_REL)).resolve()
        else:
            directory = resolve_cli_directory(args.directory, root)
        scan = scan_directory(directory, root=root)
        extras = {}
        if args.make_zip:
            output = args.output if args.output is not None else root.joinpath(*DEFAULT_OUTPUT_REL)
            if not output.is_absolute():
                output = root / output
            zip_path, manifest_path = create_bundle(scan, output)
            extras = {
                "zip": {"path": _display_path(zip_path, root), "size": zip_path.stat().st_size,
                        "sha256": sha256_file(zip_path)},
                "manifest": _display_path(manifest_path, root),
            }
        print(json.dumps(_summary("PASS", scan, root, extras), indent=2, sort_keys=True))
        return 0
    except GateError as error:
        print(json.dumps({
            "status": "FAIL",
            "gateVersion": GATE_VERSION,
            "code": error.code,
            "path": error.path,
            "detail": error.detail,
        }, sort_keys=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
