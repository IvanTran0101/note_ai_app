#!/usr/bin/env python3
"""Prepare pinned public data only; no provider key or tokenizer code is executed."""
from pathlib import Path
import hashlib
import io
import json
import shutil
import urllib.request
import zipfile


def prepare(root: Path):
    manifest = json.loads((root / 'docs/rag/deepseek_tokenizer_manifest.json').read_text())
    target = root / 'output/rag/deepseek-tokenizer'
    target.mkdir(parents=True, exist_ok=True)
    def verified(name):
        path = target / name
        return path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == manifest['files'][name]
    if not all(verified(name) for name in manifest['files']):
        with urllib.request.urlopen(manifest['source'], timeout=30) as response:
            body = response.read(30 * 1024 * 1024 + 1)
        if len(body) > 30 * 1024 * 1024 or hashlib.sha256(body).hexdigest() != manifest['archiveSha256']:
            raise ValueError('Official tokenizer archive checksum mismatch')
        with zipfile.ZipFile(io.BytesIO(body)) as archive:
            for name, digest in manifest['files'].items():
                data = archive.read('deepseek_v4_tokenizer/' + name)
                if hashlib.sha256(data).hexdigest() != digest:
                    raise ValueError('Tokenizer file checksum mismatch')
                (target / name).write_bytes(data)
    layer = root / 'output/rag/phase4-tokenizer-layer'
    for folder, spec in [('tokenizer', 'tokenizer_manifest.json'), ('deepseek-tokenizer', 'deepseek_tokenizer_manifest.json')]:
        file_manifest = json.loads((root / 'docs/rag' / spec).read_text())
        (layer / folder).mkdir(parents=True, exist_ok=True)
        for name, digest in file_manifest['files'].items():
            origin = root / 'output/rag' / folder / name
            if hashlib.sha256(origin.read_bytes()).hexdigest() != digest:
                raise ValueError('Prepare Cohere tokenizer first; pinned file missing or modified')
            shutil.copy2(origin, layer / folder / name)
    return layer


if __name__ == '__main__':
    print(prepare(Path(__file__).resolve().parents[2]))
