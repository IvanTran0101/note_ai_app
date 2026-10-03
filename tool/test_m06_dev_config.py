"""Local configuration boundary tests. No AWS account, network or deployment."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import m06_dev_config as config


class DevConfigTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.env = self.root / ".env"

    def outputs(self):
        value = {"auth": {"aws_region": "ap-southeast-1", "user_pool_id": "synthetic-pool",
                          "user_pool_client_id": "synthetic-client"}, "version": "1.5",
                 "custom": {"syncApiEndpoint": "https://sync.example.invalid",
                            "eventHttpEndpoint": "https://events.example.invalid/event",
                            "eventSocketEndpoint": "wss://socket.example.invalid/event/realtime"}}
        path = self.root / "outputs.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return value

    def test_env_quotes_comments_equals_and_no_expansion(self):
        self.env.write_text("# comment\nAWS_PROFILE='dev'\nAWS_SECRET_ACCESS_KEY=literal=$VALUE\n", encoding="utf-8")
        self.assertEqual(config.read_env(self.env), {"AWS_PROFILE": "dev", "AWS_SECRET_ACCESS_KEY": "literal=$VALUE"})

    def test_invalid_duplicate_unknown_and_unclosed_quote(self):
        for text in ("AWS_PROFILE=x\nAWS_PROFILE=y", "UNRECOGNIZED=value", "AWS_PROFILE='value", "no-equals"):
            with self.subTest(text=text):
                self.env.write_text(text, encoding="utf-8")
                with self.assertRaises(ValueError):
                    config.read_env(self.env)

    def test_auth_pair_and_profile_are_unambiguous(self):
        for values in ({"AWS_ACCESS_KEY_ID": "synthetic"}, {"AWS_SESSION_TOKEN": "synthetic"},
                       {"AWS_PROFILE": "dev", "AWS_ACCESS_KEY_ID": "a", "AWS_SECRET_ACCESS_KEY": "s"}):
            with self.subTest(keys=list(values)):
                with self.assertRaises(ValueError):
                    config.validate_auth(values)

    def test_local_build_contains_no_private_auth_or_cloud_config(self):
        values = {"NOTEFLOW_AUTH_MODE": "local", "AWS_ACCESS_KEY_ID": "synthetic-access",
                  "AWS_SECRET_ACCESS_KEY": "synthetic-secret", "AWS_SESSION_TOKEN": "synthetic-token"}
        self.assertEqual(config.public_defines(values, self.root), {"NOTEFLOW_AUTH_MODE": "local"})

    def test_cognito_build_uses_selected_outputs_and_public_overrides(self):
        original = self.outputs()
        values = {"NOTEFLOW_AUTH_MODE": "cognito", "NOTEFLOW_AMPLIFY_OUTPUTS_FILE": "outputs.json",
                  "NOTEFLOW_SYNC_API": "https://override.example.invalid", "AWS_SECRET_ACCESS_KEY": "never-emitted"}
        result = config.public_defines(values, self.root)
        self.assertEqual(json.loads(result["NOTEFLOW_AMPLIFY_OUTPUTS"]), original)
        self.assertEqual(result["NOTEFLOW_SYNC_API"], "https://override.example.invalid")
        self.assertNotIn("never-emitted", json.dumps(result))
        self.assertFalse(set(config.KEYS) & set(result))

    def test_cognito_requires_intended_outputs_and_complete_m06_endpoints(self):
        self.outputs()
        with self.assertRaises(ValueError):
            config.public_defines({"NOTEFLOW_AUTH_MODE": "cognito"}, self.root)
        value = self.outputs()
        del value["custom"]["eventSocketEndpoint"]
        (self.root / "outputs.json").write_text(json.dumps(value), encoding="utf-8")
        with self.assertRaises(ValueError):
            config.public_defines({"NOTEFLOW_AUTH_MODE": "cognito", "NOTEFLOW_AMPLIFY_OUTPUTS_FILE": "outputs.json"}, self.root)

    def test_secret_in_public_outputs_is_rejected(self):
        for field in ("AWS_SECRET_ACCESS_KEY", "user_pool_client_secret", "provider_api_key"):
            with self.subTest(field=field):
                value = self.outputs()
                value["custom"][field] = "synthetic-secret"
                (self.root / "outputs.json").write_text(json.dumps(value), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "Private credential field"):
                    config.public_defines({"NOTEFLOW_AUTH_MODE": "cognito", "NOTEFLOW_AMPLIFY_OUTPUTS_FILE": "outputs.json"}, self.root)

    def test_endpoint_credentials_query_fragments_and_wrong_schemes_fail(self):
        for value in ("http://example.invalid", "https://user:secret@example.invalid", "https://example.invalid?token=a", "https://example.invalid#token"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    config.endpoint(value, "https")

    def test_profile_clears_inherited_keys_and_leaves_parent_unchanged(self):
        parent = {"AWS_ACCESS_KEY_ID": "old", "AWS_SECRET_ACCESS_KEY": "old", "AWS_SESSION_TOKEN": "old", "AWS_DEFAULT_PROFILE": "old"}
        result = config.backend_environment({"AWS_PROFILE": "dev", "AWS_REGION": "region"}, parent)
        self.assertEqual(result["AWS_PROFILE"], "dev")
        self.assertEqual(result["AWS_DEFAULT_REGION"], "region")
        self.assertFalse(set(config.KEYS) & set(result))
        self.assertEqual(parent["AWS_ACCESS_KEY_ID"], "old")

    def test_temporary_keys_clear_inherited_profile_and_token(self):
        values = {"AWS_ACCESS_KEY_ID": "new", "AWS_SECRET_ACCESS_KEY": "new"}
        result = config.backend_environment(values, {"AWS_PROFILE": "old", "AWS_DEFAULT_PROFILE": "old", "AWS_SESSION_TOKEN": "old"})
        self.assertNotIn("AWS_PROFILE", result)
        self.assertNotIn("AWS_SESSION_TOKEN", result)

    def test_generated_output_cannot_escape_ignored_directory(self):
        for value in (".env", "lib/config.json", "output/../lib/config.json", "output"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    config.output_path(value)

    def test_prepare_cli_and_backend_child_do_not_log_synthetic_credentials(self):
        self.env.write_text("NOTEFLOW_AUTH_MODE=local\nAWS_ACCESS_KEY_ID=synthetic-access\nAWS_SECRET_ACCESS_KEY=synthetic-secret\n", encoding="utf-8")
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(config, "ROOT", self.root), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(config.main(["--env", str(self.env), "prepare"]), 0)
            self.assertEqual(config.main(["--env", str(self.env), "backend", "--", sys.executable, "-c",
                "import os; assert os.environ['AWS_ACCESS_KEY_ID']=='synthetic-access'"]), 0)
        generated = (self.root / "output/m06-dev/dart-defines.json").read_text()
        for value in ("synthetic-access", "synthetic-secret"):
            self.assertNotIn(value, stdout.getvalue() + stderr.getvalue() + generated)

    def test_json_parse_error_does_not_echo_source_text(self):
        self.env.write_text("NOTEFLOW_AUTH_MODE=cognito\nNOTEFLOW_AMPLIFY_OUTPUTS_FILE=outputs.json", encoding="utf-8")
        (self.root / "outputs.json").write_text("synthetic-sensitive-invalid-json", encoding="utf-8")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(config.main(["--env", str(self.env), "prepare"]), 2)
        self.assertNotIn("synthetic-sensitive", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
