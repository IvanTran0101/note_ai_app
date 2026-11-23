#!/usr/bin/env python3
"""IAM-only synthetic backfill/recovery. Never replays note text from a failed event."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import uuid

PROFILE = 'noteflow-dev'
REGION = 'ap-southeast-1'

def payload(owner: str, recover: bool = False) -> dict:
    if not re.fullmatch(r'rag-smoke-[A-Za-z0-9._-]{1,110}', owner):
        raise ValueError('SYNTHETIC_ONLY')
    if recover:
        return {'operation': 'recover', 'ownerId': owner}
    return {'operation': 'reconcile', 'job': {
        'jobVersion': 1, 'kind': 'RECONCILE_ACCOUNT', 'ownerId': owner,
        'noteId': None, 'sourceRevisionHint': None, 'policyVersion': 'rag-index.v1',
        'eventId': 'manual-' + uuid.uuid4().hex,
    }}

def invoke(worker: str, owner: str, recover: bool = False) -> dict:
    body = payload(owner, recover)
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', worker) or 'RagWorker' not in worker:
        raise ValueError('INVALID_WORKER')
    with tempfile.TemporaryDirectory(prefix='noteflow-rag-job-') as directory:
        request = Path(directory) / 'request.json'
        response = Path(directory) / 'response.json'
        request.write_text(json.dumps(body))
        result = subprocess.run([
            'aws', '--profile', PROFILE, '--region', REGION, 'lambda', 'invoke',
            '--function-name', worker, '--cli-binary-format', 'raw-in-base64-out',
            '--payload', 'file://' + str(request), str(response), '--output', 'json',
        ], capture_output=True, text=True, env={**os.environ, 'AWS_MAX_ATTEMPTS': '1'})
        if result.returncode:
            raise RuntimeError('AWS_INVOCATION_FAILED')
        metadata = json.loads(result.stdout)
        if metadata.get('FunctionError'):
            raise RuntimeError('WORKER_FAILED')
        if not response.is_file() or response.stat().st_size > 65536:
            raise RuntimeError('INVALID_WORKER_RESPONSE')
        value = json.loads(response.read_text())
        if not isinstance(value, dict) or not set(value) <= {
            'status', 'code', 'manifestVersion', 'retired', 'orphans'}:
            raise RuntimeError('INVALID_WORKER_RESPONSE')
        return value

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worker', required=True)
    parser.add_argument('--owner', required=True)
    parser.add_argument('--recover', action='store_true')
    args = parser.parse_args()
    print(json.dumps(invoke(args.worker, args.owner, args.recover)))
