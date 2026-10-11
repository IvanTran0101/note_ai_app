"""Meaningful malformed-input and source-isolation tests for the fixture oracle."""
import copy
import math
import unittest
from pathlib import Path
from phase1_contract import (ContractError, authorize_fixture, load_json, merge_ranges,
                             mock_decision, rrf_order, source_slice, validate_request,
                             validate_response, eligible)
from check_phase1 import check_policy

ROOT = Path(__file__).resolve().parents[2]
POLICY = load_json((ROOT / "docs/rag/policy_v1.json").read_text())
NOTES = {n["key"]: n for n in load_json((ROOT / "test/fixtures/rag/notes.json").read_text())["notes"]}
CASES = load_json((ROOT / "test/fixtures/rag/query_cases.json").read_text())["cases"]


class ContractBoundaryTests(unittest.TestCase):
    def test_integral_json_number_matches_js_safe_integer(self):
        request = copy.deepcopy(CASES[0]["request"])
        request["wireVersion"] = 1.0
        validate_request(request, POLICY)
        self.assertEqual(source_slice("abcd", 0.0, 2.0), "ab")

    def test_owner_sharing_out_does_not_change_ownership(self):
        note = {**NOTES["a-watch"], "sharedOut": True}
        self.assertTrue(eligible(note, "actor-a"))
        self.assertFalse(eligible(note, "actor-b"))

    def test_release_rechecks_revoked_consent(self):
        wire = load_json((ROOT / "test/fixtures/rag/wire_cases.json").read_text())
        response = wire["responses"][0]["payload"]
        case = copy.deepcopy(CASES[0])
        case["consent"]["accepted"] = False
        with self.assertRaisesRegex(ContractError, "CONSENT_REQUIRED"):
            validate_response(response, case, NOTES, POLICY)

    def test_true_false_criteria_flip_rejected(self):
        changed = copy.deepcopy(POLICY)
        c = changed["jev"]["questions"]["answerable_from_evidence"]["criteria"]
        c["true"], c["false"] = c["false"], c["true"]
        with self.assertRaises(ContractError):
            check_policy(changed)

    def test_duplicate_json_keys_rejected(self):
        with self.assertRaises(ContractError):
            load_json('{"scope":{"type":"account","type":"note"}}')

    def test_nan_json_rejected(self):
        with self.assertRaises(ContractError):
            load_json('{"noul":NaN}')

    def test_bool_is_not_wire_version(self):
        request = copy.deepcopy(CASES[0]["request"])
        request["wireVersion"] = True
        with self.assertRaises(ContractError):
            validate_request(request, POLICY)

    def test_owner_injection_rejected(self):
        request = copy.deepcopy(CASES[0]["request"])
        request["ownerId"] = "actor-b"
        with self.assertRaises(ContractError):
            validate_request(request, POLICY)

    def test_lone_surrogate_rejected(self):
        request = copy.deepcopy(CASES[0]["request"])
        request["question"] = "\ud800"
        with self.assertRaises(ContractError):
            validate_request(request, POLICY)

    def test_utf8_budget_not_character_ratio(self):
        request = copy.deepcopy(CASES[0]["request"])
        request["question"] = "🧠" * 1025
        with self.assertRaises(ContractError):
            validate_request(request, POLICY)

    def test_source_offsets_do_not_bisect_emoji(self):
        self.assertEqual(source_slice("A 🧠 B", 2, 4), "🧠")
        with self.assertRaises(ContractError):
            source_slice("A 🧠 B", 3, 4)

    def test_cross_account_same_note_id_denied(self):
        with self.assertRaisesRegex(ContractError, "SCOPE_DENIED"):
            authorize_fixture(CASES[9], NOTES)

    def test_consent_revoke_denied(self):
        with self.assertRaisesRegex(ContractError, "CONSENT_REQUIRED"):
            authorize_fixture(CASES[18], NOTES)

    def test_session_generation_change_denied(self):
        case = copy.deepcopy(CASES[0])
        case["sessionGeneration"] = 2
        with self.assertRaisesRegex(ContractError, "SOURCE_CHANGED"):
            authorize_fixture(case, NOTES)

    def test_unset_live_thresholds_never_allow(self):
        self.assertEqual(mock_decision(CASES[0]["providerMock"]["jev"], None),
                         ("ERROR", "LIVE_POLICY_NOT_CONFIGURED"))

    def test_nonfinite_probability_never_allows(self):
        envelope = copy.deepcopy(CASES[0]["providerMock"]["jev"])
        envelope["answers"]["answerable_from_evidence"]["noul"] = math.inf
        self.assertEqual(mock_decision(envelope, POLICY["mockOnly"]["thresholds"])[0], "ERROR")

    def test_bool_threshold_rejected(self):
        with self.assertRaises(ContractError):
            mock_decision(CASES[0]["providerMock"]["jev"],
                          {"answerabilityMin": True, "conflictMax": 0.1})

    def test_conflict_wins_even_when_support_high(self):
        self.assertEqual(mock_decision(CASES[4]["providerMock"]["jev"],
                                      POLICY["mockOnly"]["thresholds"]),
                         ("NOT_ENOUGH_CONTEXT", "UNRESOLVED_CONFLICT"))

    def test_uncertainty_not_partial_answer(self):
        self.assertEqual(mock_decision(CASES[23]["providerMock"]["jev"],
                                      POLICY["mockOnly"]["thresholds"]),
                         ("NOT_ENOUGH_CONTEXT", "UNCERTAIN"))

    def test_same_branch_duplicate_not_double_counted(self):
        self.assertEqual(rrf_order([["A", "A", "B"], ["B", "A"]]), ["A", "B"])

    def test_tie_is_stable(self):
        self.assertEqual(rrf_order([["B"], ["A"]]), ["A", "B"])

    def test_dedupe_does_not_merge_different_revision(self):
        span = dict(ownerId="actor-a", noteId="n-watch", revision=1,
                    sectionId="s1", startOffset=0, endOffset=10)
        other = {**span, "revision": 2}
        self.assertEqual(len(merge_ranges([span, other])), 2)


if __name__ == "__main__":
    unittest.main()
