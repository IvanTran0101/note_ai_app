"""Opt-in HTTP checks for run_m06_local.py, using only its fixed demo users."""
import base64
import json
import os
from pathlib import Path
import time
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def credential(actor="m06-dev-owner", **changes):
    claims = dict(sub=actor, token_use="access", iss="m06-local-dev", exp=int(time.time()) + 600)
    claims.update(changes)
    encoded = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
    return "Bearer e30." + encoded + ".local-dev"


def request(path, *, auth=None, body=None, headers=None, method=None):
    values = dict(headers or {})
    if auth:
        values["Authorization"] = auth
    data = None if body is None else json.dumps(body).encode()
    if data:
        values["Content-Type"] = "application/json"
    req = Request("http://127.0.0.1:8796" + path, data=data, headers=values, method=method)
    try:
        reply = urlopen(req, timeout=5)
    except HTTPError as error:
        reply = error
    with reply:
        raw = reply.read()
        return reply.status, json.loads(raw) if raw else None


@unittest.skipUnless(os.environ.get("RUN_M06_LOCAL_HTTP") == "1", "opt-in loopback dev server")
class LocalServerTest(unittest.TestCase):
    def test_health(self):
        self.assertEqual(request("/dev/health"), (200, {"kind": "m06-local-dev", "version": 1}))

    def test_anonymous_and_real_provider_marker_are_refused(self):
        self.assertEqual(request("/sync/changes")[0], 401)
        self.assertEqual(request("/sync/changes", auth=credential().replace(".local-dev", ".cognito"))[0], 401)

    def test_unknown_actor_is_refused(self):
        self.assertEqual(request("/sync/changes", auth=credential("real-account"))[0], 401)

    def test_expired_token_is_refused(self):
        self.assertEqual(request("/sync/changes", auth=credential(exp=1))[0], 401)

    def test_issuer_and_token_use_are_refused(self):
        self.assertEqual(request("/sync/changes", auth=credential(iss="provider"))[0], 401)
        self.assertEqual(request("/sync/changes", auth=credential(token_use="id"))[0], 401)

    def test_foreign_origin_and_host_are_refused(self):
        self.assertEqual(request("/sync/changes", auth=credential(), headers={"Origin": "https://cloud.example"})[0], 403)
        self.assertEqual(request("/dev/health", headers={"Host": "cloud.example"})[0], 403)

    def test_unknown_routes_do_not_mutate(self):
        self.assertEqual(request("/other", auth=credential())[0], 404)

    def test_owner_feed_is_available(self):
        status, value = request("/sync/changes", auth=credential())
        self.assertEqual(status, 200)
        self.assertIn("items", value)

    def test_revoked_recipient_cannot_write_content_or_manage(self):
        status, value = request("/sync/changes", auth=credential())
        self.assertEqual(status, 200)
        rows = [n for n in value["items"] if n.get("title") == "M06 local Share demo"]
        self.assertTrue(rows, "Create and revoke the UI demo share first")
        note = max(rows, key=lambda n: n["revision"])
        recipient = credential("m06-dev-recipient")
        path = "/notes/" + note["id"]
        self.assertEqual(request(path + "/content?ownerId=m06-dev-owner", auth=recipient)[0], 403)
        self.assertEqual(request(path + "/shares?ownerId=m06-dev-owner", auth=recipient)[0], 403)
        mutation = dict(mutationId="denied-dev-probe", noteId=note["id"], ownerId="m06-dev-owner",
                        accessRevision=1, baseRevision=note["revision"], operation="update",
                        payload=dict(title="Must not be written", content="Denied"))
        self.assertEqual(request("/sync/shared-mutations", auth=recipient, body=mutation)[0], 403)

    def test_disk_snapshot_contains_no_demo_plaintext(self):
        packet = (Path(__file__).resolve().parents[1] / "output/m06-local/database.enc").read_bytes()
        self.assertEqual(packet[0], 1)
        self.assertNotIn(b"M06 local Share demo", packet)
        self.assertNotIn(b"Owner reply after recipient edit", packet)


if __name__ == "__main__":
    unittest.main()
