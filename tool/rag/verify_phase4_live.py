#!/usr/bin/env python3
"""Serialized IAM-only synthetic gate; no key access, retries or real-user notes."""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import time

ROOT = Path('output/rag/phase4/final-gates')


def invoke(function, event, path):
    input_path = path.with_name(path.stem + '-input.json')
    input_path.write_text(json.dumps(event))
    started = time.monotonic()
    metadata = json.loads(subprocess.check_output([
        'aws', 'lambda', 'invoke', '--function-name', function,
        '--cli-binary-format', 'raw-in-base64-out', '--payload',
        'fileb://' + str(input_path.resolve()), '--profile', 'noteflow-dev',
        '--region', 'ap-southeast-1', str(path.resolve()),
    ], env={**os.environ, 'AWS_MAX_ATTEMPTS': '1'}, timeout=40, text=True))
    if metadata.get('FunctionError'):
        raise RuntimeError('Private Lambda error; no retry')
    result = json.loads(path.read_text())
    result['operatorWallMs'] = round((time.monotonic() - started) * 1000)
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return result


def check_answer(result, fixture):
    assert result.get('status') == 'ANSWERED', 'Expected answer; retain failure without retry'
    assert result['sources'], 'Answer without sources'
    approved = {source['sourceId']: source for source in fixture['evidence']['sources']}
    for source in result['sources']:
        assert source == approved.get(source['sourceId']), 'Source differs from frozen evidence'
        assert '[' + source['sourceId'] + ']' in result['answer'], 'Inline citation missing'
    assert result['elapsedMs'] <= 26000, 'Backend deadline exceeded'


def check_query(result, expected, note=None):
    response = result.get('response', {})
    assert response.get('status') == expected, 'Unexpected result; retain without retry/retune'
    assert result['elapsedMs'] <= 26000, 'Backend deadline exceeded'
    if expected != 'ANSWERED':
        assert response['answer'] is None and response['sources'] == []
        assert not any(usage['model'] == 'deepseek-flash' for usage in result['usage'])
        return
    assert response['sources'] and note is not None
    assert not re.search(r'\b(?:19|20)\d{2}\b', response['answer']), 'Invented year'
    # Backend source offsets are UTF-16 code units, not Python code points.
    raw = note['content'].encode('utf-16-le')
    for source in response['sources']:
        assert source['noteId'] == note['id'] and source['revision'] == note['revision']
        assert 0 <= source['startOffset'] < source['endOffset'] <= len(raw) // 2
        assert raw[source['startOffset'] * 2:source['endOffset'] * 2].decode('utf-16-le') == source['quote']
        assert '[' + source['sourceId'] + ']' in response['answer'], 'Inline citation missing'
    assert all(value.lower() in response['answer'].lower() for value in note['expectedFacts'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--function', required=True)
    parser.add_argument('--mode', choices=['answers', 'query'], required=True)
    args = parser.parse_args()
    assert re.fullmatch(r'[A-Za-z0-9_-]{1,64}', args.function) and 'ragquerylambda' in args.function
    ROOT.mkdir(parents=True, exist_ok=True)
    fixtures = {fixture['id']: fixture for fixture in json.loads(
        Path('test/fixtures/rag/phase4/fixtures.json').read_text())['fixtures']}
    if args.mode == 'answers':
        report = json.loads((ROOT / 'confirmation-report.json').read_text())
        assert report['gates']['passed'], 'No passing confirmation'
        ids = [row['fixtureId'] for row in report['outcomes'] if row['verdict'] == 'ALLOW'] + ['fx-dev-vi-ans-05']
        assert len(ids) <= 8, 'Answer gate bounded to 8 calls'
        for fixture_id in ids:
            path = ROOT / ('fixed-answer-' + fixture_id + '.json')
            result = json.loads(path.read_text()) if path.exists() else invoke(
                args.function, {'operation': 'answer-fixture', 'fixtureId': fixture_id}, path)
            check_answer(result, fixtures[fixture_id])
            print(json.dumps({'fixtureId': fixture_id, 'status': result['status'],
                              'answer': result['answer'], 'elapsedMs': result['elapsedMs']}, ensure_ascii=False), flush=True)
        return
    native = json.loads((ROOT / 'native-vi-note.json').read_text())
    native['expectedFacts'] = ['12 tháng 11', 'phòng F']
    recovery = {'id': 'recovery', 'revision': 2,
                'content': 'Synthetic current revision 2: launch is 25 October.',
                'expectedFacts': ['25 October']}
    # Preserve the observed cross-language refusal; do not replace it with a retry.
    cases = [
        ('en', 'rag-smoke-recovery-e9cae4f4', 'What is the launch date stated in this note?', 'ANSWERED', recovery),
        ('vi', 'rag-smoke-recovery-e9cae4f4', 'Ngày ra mắt trong ghi chú là ngày nào?', 'NOT_ENOUGH_CONTEXT', None),
        ('native-vi', native['owner'], 'Dự án Hoa Sen ra mắt ngày nào và ở đâu?', 'ANSWERED', native),
        ('empty', 'rag-smoke-20261012-52bfb267', 'What is the launch date?', 'NOT_ENOUGH_CONTEXT', None),
    ]
    for name, owner, question, expected, note in cases:
        path = ROOT / ('query-' + name + '.json')
        event = {'operation': 'query', 'ownerId': owner, 'requestId': 'phase4-full-' + name,
                 'body': json.dumps({'wireVersion': 1, 'question': question, 'scope': {'type': 'account'}})}
        result = json.loads(path.read_text()) if path.exists() else invoke(args.function, event, path)
        check_query(result, expected, note)
        if name == 'empty':
            assert result['usage'] == [], 'Empty scope called a model'
        print(json.dumps({'case': name, 'status': result['response']['status'],
                          'answer': result['response']['answer'], 'elapsedMs': result['elapsedMs'],
                          'usage': result['usage']}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
