"""Run Chrome tests using a temporary tools overlay for Windows URI bugs.

The installed Flutter SDK is never edited. Two test-server handlers in the
current SDK use Windows filesystem separators for browser URL paths, causing
CanvasKit 404s and mismatched test selectors/entrypoint literals. Normalize only those paths in
an isolated copy; all product, compiler, engine and browser code stays real.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import urljoin


def normalize_windows_test_urls(overlay):
    """Only patch the owned QA copy; preserve the installed SDK byte-for-byte."""
    replacements = {
        'lib/src/test/flutter_web_platform.dart': [
            ('final String fullPath = _fileSystem.path.fromUri(request.url);',
             'final String fullPath = request.url.path;'),
            ('window.testSelector = "$test";',
             '''window.testSelector = "${test.replaceAll(String.fromCharCode(92), '/')}";'''),
        ],
        'lib/src/web/bootstrap.dart': [
            ('final String entryPointPath = testInfo.entryPoint;',
             "final String entryPointPath = testInfo.entryPoint.replaceAll(String.fromCharCode(92), '/');"),
        ],
    }
    receipt = []
    for relative, edits in replacements.items():
        path = overlay / relative
        if not path.is_file():
            continue  # Older SDKs may not have the newer Web bootstrap file.
        before = path.read_bytes()
        source = before.decode('utf-8')
        applied = []
        for old, new in edits:
            count = source.count(old)
            if count:
                source = source.replace(old, new)
                applied.append({'original': old, 'count': count})
        if applied:
            after = source.encode('utf-8')
            path.write_bytes(after)
            receipt.append({
                'path': relative,
                'before_sha256': hashlib.sha256(before).hexdigest(),
                'after_sha256': hashlib.sha256(after).hexdigest(),
                'edits': applied,
            })
    (overlay / 'windows-url-receipt.json').write_text(
        json.dumps(receipt, indent=2), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sdk', required=True)
    parser.add_argument('--dart-define', action='append', default=[],
                        help='Explicit compile-time configuration for authorized local tests')
    parser.add_argument('--aggregate', action='store_true',
                        help='Register each target main in its own group in one Chrome compilation')
    parser.add_argument('targets', nargs='*', default=['test'])
    args = parser.parse_args()
    targets = args.targets
    if args.aggregate:
        root = Path.cwd().resolve(strict=True)
        # Flutter's Web compiler includes the test source tree but excludes
        # .dart_tool. This ignored explicit target never matches *_test.dart.
        generated = root / 'test/m05_browser_suite.generated.dart'
        imports = ["import 'package:flutter_test/flutter_test.dart';"]
        groups = []
        for index, target in enumerate(targets):
            path = Path(target).resolve(strict=True)
            if not path.is_file() or not path.is_relative_to(root):
                raise ValueError('aggregate target must be a local test file')
            source = path.read_text(encoding='utf-8')
            if "@TestOn('vm')" in source or '@TestOn("vm")' in source:
                raise ValueError(f'VM-only target cannot run in Chrome: {target}')
            relative = os.path.relpath(path, generated.parent).replace('\\', '/')
            imports.append(f'import {json.dumps(relative)} as suite{index};')
            groups.append(f'  group({json.dumps(target.replace(chr(92), "/"))}, suite{index}.main);')
        generated.write_text('\n'.join(imports) +
                             '\nvoid main() {\n' +
                             '\n'.join(groups) + '\n}\n', encoding='utf-8')
        print(f'Aggregated {len(groups)} original test mains in independent groups', flush=True)
        # Keep the CLI target relative to the active checkout alias (SUBST on
        # Windows). Mixing its physical path with the alias breaks test URLs.
        targets = [os.path.relpath(generated, root)]
    sdk = Path(args.sdk).resolve(strict=True)
    tools = sdk / 'packages/flutter_tools'
    temp_root = Path(tempfile.gettempdir()).resolve(strict=True)
    overlay = Path(tempfile.mkdtemp(prefix='m05-flutter-chrome-', dir=temp_root)).resolve()
    if not overlay.is_relative_to(temp_root):
        raise RuntimeError('overlay escaped temporary directory')
    shutil.copytree(tools / 'lib', overlay / 'lib')
    shutil.copytree(tools / 'bin', overlay / 'bin')
    if os.name == 'nt':
        normalize_windows_test_urls(overlay)
    original_config = tools / '.dart_tool/package_config.json'
    config = json.loads(original_config.read_text(encoding='utf-8'))
    for package in config['packages']:
        package['rootUri'] = (overlay.as_uri() + '/' if package['name'] == 'flutter_tools'
                              else urljoin(original_config.as_uri(), package['rootUri']))
    config_path = overlay / 'package_config.json'
    config_path.write_text(json.dumps(config), encoding='utf-8')
    env = dict(os.environ, FLUTTER_ROOT=str(sdk))
    dart = sdk / 'bin/cache/dart-sdk/bin/dart.exe'
    command = [str(dart), f'--packages={config_path}', str(overlay / 'bin/flutter_tools.dart'),
               'test', '--platform', 'chrome', '--no-pub', '--reporter', 'expanded',
               f'--file-reporter=json:{temp_root / "m05-chrome-results.jsonl"}',
               *[f'--dart-define={value}' for value in args.dart_define], *targets]
    print(f'Isolated Flutter tools: {overlay}', flush=True)
    return subprocess.call(command, env=env)


if __name__ == '__main__':
    raise SystemExit(main())
