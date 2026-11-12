#!/usr/bin/env python3
"""Download only the pinned EmbeddingGemma tokenizer into ignored output/rag/embeddinggemma-tokenizer."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = 'docs/rag/embeddinggemma_tokenizer_manifest.json'
DESTINATION = 'output/rag/embeddinggemma-tokenizer'
MAX_BYTES = 64_000_000


def prepare(destination: Path) -> None:
    manifest = json.loads((ROOT / MANIFEST).read_text())
    destination.mkdir(parents=True, exist_ok=True)
    for name, digest in manifest['files'].items():
        target = destination / name
        if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == digest:
            continue
        url = f"https://huggingface.co/{manifest['repository']}/resolve/{manifest['revision']}/{name}"
        with urllib.request.urlopen(url, timeout=120) as response:
            data = response.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES or hashlib.sha256(data).hexdigest() != digest:
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
    print('Pinned EmbeddingGemma tokenizer files verified; no model weights downloaded.')


if __name__ == '__main__':
    prepare(ROOT / DESTINATION)
