#!/usr/bin/env python3
"""Download only the pinned Cohere tokenizer into ignored output/rag/tokenizer."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]

def prepare(destination: Path) -> None:
    manifest = json.loads((ROOT / 'docs/rag/tokenizer_manifest.json').read_text())
    destination.mkdir(parents=True, exist_ok=True)
    for name, digest in manifest['files'].items():
        target = destination / name
        if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == digest:
            continue
        url = f"https://huggingface.co/{manifest['repository']}/resolve/{manifest['revision']}/{name}"
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read(20_000_001)
        if len(data) > 20_000_000 or hashlib.sha256(data).hexdigest() != digest:
            raise ValueError('TOKENIZER_HASH_MISMATCH')
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=destination, delete=False) as file:
                temporary = Path(file.name)
                file.write(data)
            os.replace(temporary, target)
        finally:
            if temporary and temporary.exists():
                temporary.unlink()
    print('Pinned tokenizer files verified; no model weights downloaded.')

if __name__ == '__main__':
    prepare(ROOT / 'output/rag/tokenizer')
