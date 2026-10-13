"""Focused stdlib tests for the Phase 5.4 static web hosting gate.

Run from anywhere with:
    python3 -m unittest tool/rag/test_prepare_web_hosting.py
"""
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import prepare_web_hosting as pwh  # noqa: E402

INDEX = b"<!doctype html><html><base href='/'>"
MAIN = b"console.log('flutter placeholder');"
BOOTSTRAP = b"window.flutterConfiguration={};"
HEADERS = b"/*\n  Cache-Control: no-cache\n  X-Content-Type-Options: nosniff\n"
ASSET = b"static asset bytes"


def write_tree(base: Path, files):
    for rel, data in files.items():
        target = base / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


def base_files():
    return {
        "index.html": INDEX,
        "main.dart.js": MAIN,
        "flutter_bootstrap.js": BOOTSTRAP,
        "assets/app.txt": ASSET,
    }


class PrepareWebHostingTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

    def make(self, extra=None, *, headers=HEADERS, approved=HEADERS, name="case"):
        root = self.root / name
        (root / "web").mkdir(parents=True)
        (root / "web" / "_headers").write_bytes(approved)
        artifact = root / "build" / "web"
        files = base_files()
        if extra:
            files.update(extra)
        write_tree(artifact, files)
        if headers is not None:
            (artifact / "_headers").write_bytes(headers)
        return root, artifact

    def test_positive_scan_and_bundle_roundtrip(self):
        root, artifact = self.make()
        scan = pwh.scan_directory(artifact, root=root)
        self.assertEqual(scan.headers_action, "present")
        self.assertEqual(len(scan.files), 5)
        zip_path, manifest_path = pwh.create_bundle(scan, root / "out")
        with zipfile.ZipFile(zip_path) as archive:
            names = sorted(archive.namelist())
        self.assertEqual(names, sorted([
            "_headers", "assets/app.txt", "flutter_bootstrap.js",
            "index.html", "main.dart.js",
        ]))
        manifest = json.loads(manifest_path.read_text())
        self.assertEqual(manifest["gateVersion"], pwh.GATE_VERSION)
        self.assertEqual(manifest["zip"]["name"], pwh.ZIP_NAME)
        self.assertEqual(manifest["zip"]["size"], zip_path.stat().st_size)
        self.assertEqual(manifest["zip"]["sha256"], hashlib.sha256(zip_path.read_bytes()).hexdigest())
        self.assertEqual(manifest["fileCount"], 5)

    def test_limits_are_the_verified_cloudflare_values(self):
        self.assertEqual(pwh.MAX_FILES, 20000)
        self.assertEqual(pwh.MAX_FILE_BYTES, 26214400)

    def test_missing_artifact_headers_are_copied_from_approved_source(self):
        root, artifact = self.make(headers=None)
        self.assertFalse((artifact / "_headers").exists())
        scan = pwh.scan_directory(artifact, root=root)
        self.assertEqual(scan.headers_action, "copied")
        self.assertEqual((artifact / "_headers").read_bytes(), HEADERS)

    def test_changed_artifact_headers_are_refused(self):
        root, artifact = self.make(headers=b"/*\n  Cache-Control: public, max-age=31536000\n")
        with self.assertRaises(pwh.GateError) as caught:
            pwh.scan_directory(artifact, root=root)
        self.assertEqual(caught.exception.code, "HEADERS_CHANGED")

    def test_secret_content_is_refused_and_redacted(self):
        secret = b"AKIA" + b"ABCDEFGHIJKLMNOP"
        root, artifact = self.make({"assets/leak.js": b"const k='" + secret + b"';"})
        with self.assertRaises(pwh.GateError) as caught:
            pwh.scan_directory(artifact, root=root)
        error = caught.exception
        self.assertEqual(error.code, "SECRET_AWS_ACCESS_KEY")
        self.assertNotIn(secret.decode(), str(error))
        self.assertNotIn("ABCDEFGHIJKLMNOP", error.detail)
        self.assertNotIn("const k", str(error))

    def test_private_key_and_sk_token_are_refused(self):
        cases = [
            ({"assets/private.txt": b"-----BEGIN RSA PRIVATE KEY-----\nMIIE\n"}, "SECRET_PRIVATE_KEY"),
            ({"assets/token.js": b"const t='sk-" + b"a" * 40 + b"';"}, "SECRET_SK_TOKEN"),
        ]
        for extra, code in cases:
            with self.subTest(code=code):
                root, artifact = self.make(extra, name=code)
                with self.assertRaises(pwh.GateError) as caught:
                    pwh.scan_directory(artifact, root=root)
                self.assertEqual(caught.exception.code, code)

    def test_env_corpus_tokenizer_and_note_fixtures_are_refused(self):
        cases = [
            ({".env": b"SECRET=1"}, "ENV_FILE"),
            ({"corpus/notes.txt": b"backend corpus"}, "CORPUS_ASSET"),
            ({"weights/model.gguf": b"GGUF"}, "CORPUS_ASSET"),
            ({"tokenizer.json": b"{}"}, "TOKENIZER_ASSET"),
            ({"fixtures/notes.json": b"[]"}, "RAW_NOTE_FIXTURE"),
            ({"notes.json": b"[]"}, "RAW_NOTE_FIXTURE"),
            ({"aws/credentials": b"[default]"}, "CREDENTIAL_FILE"),
        ]
        for index, (extra, code) in enumerate(cases):
            with self.subTest(code=code, extra=sorted(extra)):
                root, artifact = self.make(extra, name=f"{code}_{index}")
                with self.assertRaises(pwh.GateError) as caught:
                    pwh.scan_directory(artifact, root=root)
                self.assertEqual(caught.exception.code, code)

    def test_symlink_escape_is_refused(self):
        root, artifact = self.make()
        outside = root / "outside.txt"
        outside.write_bytes(b"private")
        os.symlink(outside, artifact / "assets" / "link.txt")
        with self.assertRaises(pwh.GateError) as caught:
            pwh.scan_directory(artifact, root=root)
        self.assertEqual(caught.exception.code, "SYMLINK")

    def test_symlinked_directory_is_refused(self):
        root, artifact = self.make()
        os.symlink(root, artifact / "escape")
        with self.assertRaises(pwh.GateError) as caught:
            pwh.scan_directory(artifact, root=root)
        self.assertEqual(caught.exception.code, "SYMLINK")

    def test_debug_mock_markers_are_refused(self):
        for index, marker in enumerate((b"rag-mock.invalid", b"OFFLINE RAG MOCK", b"main_rag_mock")):
            with self.subTest(marker=marker):
                root, artifact = self.make(
                    {"assets/runtime.js": b"const x='" + marker + b"';"}, name="debug" + str(index))
                with self.assertRaises(pwh.GateError) as caught:
                    pwh.scan_directory(artifact, root=root)
                self.assertEqual(caught.exception.code, "DEBUG_MOCK_MARKER")

    def test_size_and_count_limits_use_injected_test_quota(self):
        root, artifact = self.make({"assets/exact.bin": b"a" * 1024}, name="size_ok")
        scan = pwh.scan_directory(artifact, root=root, max_file_bytes=1024)
        self.assertEqual(len(scan.files), 6)

        root, artifact = self.make({"assets/over.bin": b"a" * 1025}, name="size_bad")
        with self.assertRaises(pwh.GateError) as caught:
            pwh.scan_directory(artifact, root=root, max_file_bytes=1024)
        self.assertEqual(caught.exception.code, "FILE_TOO_LARGE")

        root, artifact = self.make(name="count_bad")
        with self.assertRaises(pwh.GateError) as caught:
            pwh.scan_directory(artifact, root=root, max_files=4)
        self.assertEqual(caught.exception.code, "TOO_MANY_FILES")

        root, artifact = self.make(name="count_ok")
        scan = pwh.scan_directory(artifact, root=root, max_files=5)
        self.assertEqual(len(scan.files), 5)

    def test_no_bundle_is_written_when_invalid(self):
        root, artifact = self.make({"assets/leak.js": b"AKIA" + b"ABCDEFGHIJKLMNOP"}, name="bad")
        out = root / "out"
        with self.assertRaises(pwh.GateError):
            scan = pwh.scan_directory(artifact, root=root)
            pwh.create_bundle(scan, out)
        self.assertFalse((out / pwh.ZIP_NAME).exists())
        self.assertFalse((out / pwh.MANIFEST_NAME).exists())

    def test_changed_bytes_after_scan_are_refused(self):
        root, artifact = self.make(name="changed")
        scan = pwh.scan_directory(artifact, root=root)
        (artifact / "main.dart.js").write_bytes(MAIN + b"// changed after scan")
        out = root / "out"
        with self.assertRaises(pwh.GateError) as caught:
            pwh.create_bundle(scan, out)
        self.assertEqual(caught.exception.code, "CHANGED_SINCE_SCAN")
        self.assertFalse((out / pwh.ZIP_NAME).exists())
        self.assertFalse((out / pwh.MANIFEST_NAME).exists())

    def test_cli_directory_is_confined_to_build_tree(self):
        with self.assertRaises(pwh.GateError) as caught:
            pwh.resolve_cli_directory(self.root, self.root)
        self.assertEqual(caught.exception.code, "WHOLE_PROJECT")

        with self.assertRaises(pwh.GateError) as caught:
            pwh.resolve_cli_directory(self.root.parent, self.root)
        self.assertEqual(caught.exception.code, "WHOLE_PROJECT")

        outside_repo = self.root.parent / "outside_repo_marker"
        with self.assertRaises(pwh.GateError) as caught:
            pwh.resolve_cli_directory(outside_repo, self.root)
        self.assertEqual(caught.exception.code, "OUTSIDE_REPO")

        outside_build = self.root / "web"
        outside_build.mkdir(parents=True, exist_ok=True)
        with self.assertRaises(pwh.GateError) as caught:
            pwh.resolve_cli_directory(outside_build, self.root)
        self.assertEqual(caught.exception.code, "OUTSIDE_BUILD")

    def test_cli_main_passes_with_zip_and_fails_closed(self):
        root, artifact = self.make(name="cli_ok")
        output = root / "out"
        with redirect_stdout(io.StringIO()):
            code = pwh.main(["--root", str(root), "--directory", str(artifact),
                             "--output", str(output), "--zip"])
        self.assertEqual(code, 0)
        self.assertTrue((output / pwh.ZIP_NAME).is_file())
        self.assertTrue((output / pwh.MANIFEST_NAME).is_file())

        root, artifact = self.make({"assets/leak.js": b"AKIA" + b"ABCDEFGHIJKLMNOP"}, name="cli_bad")
        with redirect_stdout(io.StringIO()):
            code = pwh.main(["--root", str(root), "--directory", str(artifact)])
        self.assertEqual(code, 2)

    def test_output_inside_artifact_is_refused(self):
        root, artifact = self.make(name="output_guard")
        scan = pwh.scan_directory(artifact, root=root)
        with self.assertRaises(pwh.GateError) as caught:
            pwh.create_bundle(scan, artifact / "nested")
        self.assertEqual(caught.exception.code, "OUTPUT_INSIDE_ARTIFACT")

    def test_content_scan_and_hash_share_one_pass(self):
        # Old hole: scan_content read the file, then sha256_file opened it again,
        # so a same-length swap in between shipped under the new digest.
        secret = b"AKIA" + b"ABCDEFGHIJKLMNOP"
        payload = b"const k='" + secret + b"';"
        clean = b"0" * len(payload)  # same length: a size check cannot tell them apart
        root, artifact = self.make({"assets/app.txt": clean}, name="race_content_hash")
        target = artifact / "assets" / "app.txt"
        real_scan_content = pwh.scan_content
        real_sha256_file = pwh.sha256_file
        resolved_target = target.resolve()
        state = {"mutated": False}

        def mutate_once():
            if not state["mutated"]:
                state["mutated"] = True
                target.write_bytes(payload)

        def legacy_scan_content(path, patterns=pwh._CONTENT_PATTERNS):
            result = real_scan_content(path, patterns)
            if Path(path).resolve() == resolved_target:
                mutate_once()  # the old swap point, after the content verdict
            return result

        def legacy_sha256_file(path, *, chunk=pwh._READ_CHUNK):
            if Path(path).resolve() == resolved_target:
                mutate_once()  # the old swap point, before the digest
            return real_sha256_file(path, chunk=chunk)

        with mock.patch.object(pwh, "scan_content", legacy_scan_content), \
                mock.patch.object(pwh, "sha256_file", legacy_sha256_file):
            scan = pwh.scan_directory(artifact, root=root)

        # The one-pass scan never consults the legacy split helpers, so the
        # artifact cannot be swapped between the verdict and the digest.
        self.assertFalse(state["mutated"])
        self.assertEqual(target.read_bytes(), clean)
        entry = next(item for item in scan.files if item.relative == "assets/app.txt")
        self.assertEqual(entry.sha256, hashlib.sha256(clean).hexdigest())

        out = root / "out"
        zip_path, _manifest = pwh.create_bundle(scan, out)
        with zipfile.ZipFile(zip_path) as archive:
            self.assertNotIn(secret, archive.read("assets/app.txt"))
        self.assertEqual(target.read_bytes(), clean)

    def test_scan_stream_flags_and_hashes_the_same_bytes(self):
        # A secret that only appears after the first read is still part of the
        # same streamed bytes, so the verdict and the digest cannot disagree.
        class _Blocks:
            def __init__(self, blocks):
                self._blocks = list(blocks)

            def read(self, size=-1):
                return self._blocks.pop(0) if self._blocks else b""

        secret = b"AKIA" + b"ABCDEFGHIJKLMNOP"
        first = b"clean-prefix-" * 8
        second = b"const k='" + secret + b"';"
        flagged, digest, size = pwh.scan_stream(_Blocks([first, second]))
        self.assertEqual(flagged, "SECRET_AWS_ACCESS_KEY")
        self.assertEqual(digest, hashlib.sha256(first + second).hexdigest())
        self.assertEqual(size, len(first) + len(second))

    def test_scan_content_wrapper_still_reports_a_matched_shape(self):
        root, artifact = self.make(
            {"assets/leak.js": b"const k='" + b"AKIAABCDEFGHIJKLMNOP" + b"';"},
            name="content_wrapper")
        self.assertEqual(
            pwh.scan_content(artifact / "assets" / "leak.js"), "SECRET_AWS_ACCESS_KEY")
        self.assertIsNone(pwh.scan_content(artifact / "index.html"))

    def test_mutation_during_copy_is_refused_and_prior_bundle_preserved(self):
        secret = b"AKIA" + b"ABCDEFGHIJKLMNOP"
        payload = b"const k='" + secret + b"';"
        clean = b"0" * len(payload)  # same length, so only the digest can catch it
        root, artifact = self.make({"assets/app.txt": clean}, name="race_copy")
        target = artifact / "assets" / "app.txt"
        out = root / "out"

        good_scan = pwh.scan_directory(artifact, root=root)
        zip_path, manifest_path = pwh.create_bundle(good_scan, out)
        good_zip = zip_path.read_bytes()
        good_manifest = manifest_path.read_bytes()

        scan = pwh.scan_directory(artifact, root=root)
        real_copyfileobj = pwh.shutil.copyfileobj
        order = [item.relative for item in scan.files]
        target_index = order.index("assets/app.txt")
        state = {"calls": 0, "fired": False}

        def racy_copyfileobj(fsrc, fdst, length=0):
            index = state["calls"]
            state["calls"] += 1
            if index == target_index and not state["fired"]:
                state["fired"] = True
                target.write_bytes(payload)  # swap while this file's reader is open
            return real_copyfileobj(fsrc, fdst, length)

        with mock.patch.object(pwh.shutil, "copyfileobj", racy_copyfileobj):
            with self.assertRaises(pwh.GateError) as caught:
                pwh.create_bundle(scan, out)

        self.assertEqual(caught.exception.code, "CHANGED_DURING_COPY")
        self.assertTrue(state["fired"])
        # The swapped secret is never echoed, never published, and any partial
        # zip this run owned is gone; the prior good bundle is byte-identical.
        self.assertNotIn("AKIA", str(caught.exception))
        self.assertNotIn("const k", str(caught.exception))
        self.assertFalse((out / (pwh.ZIP_NAME + ".part")).exists())
        self.assertEqual(zip_path.read_bytes(), good_zip)
        self.assertEqual(manifest_path.read_bytes(), good_manifest)
        with zipfile.ZipFile(zip_path) as archive:
            self.assertNotIn(secret, archive.read("assets/app.txt"))


if __name__ == "__main__":
    unittest.main()
