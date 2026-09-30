#!/usr/bin/env python3
"""Offline contract-asset checks for the NoteFlow Summary Cloud Phase 1 slice.

Validates docs/summary_cloud/wire_cases.json against the frozen decisions in
docs/summary_api_contract.md. Fixture-only oracles: no DeepSeek Summary API call,
no product/Dart import, no real token measurement; token fixtures are synthetic.

Run from any cwd:  python3 docs/summary_cloud/check_contract.py
Exit: 0 = assets consistent, 1 = mismatch or malformed fixture, 2 = unreadable fixture.
"""
from __future__ import annotations

import json
import sys
from copy import deepcopy
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIXTURES_PATH = HERE / "wire_cases.json"

# Frozen Phase 1 decisions: this table is the oracle; fixture data must match it.
FROZEN = {
    "provider_model": "deepseek-flash", "thinking": "disabled", "stream": False,
    "max_input_tokens_per_call": 16000,
    "max_output_tokens": {"direct": 256, "section": 128, "merge": 256},
    "chunk_count_range": [2, 4], "merge_calls_per_pipeline": 1, "max_generation_calls": 5,
    "automatic_generation_retry": False, "success_finish_reasons": ["stop"],
    "consent_version": "summary-cloud-v1", "consent_accepted_required": True,
    "max_body_bytes_utf8": 262144, "stages": ["direct", "section", "merge"],
    "stage_input_cardinality": {"direct": [1, 1], "section": [1, 1], "merge": [2, 4]},
    "request_allowed_fields": ["consent", "inputs", "stage"],
    "consent_allowed_fields": ["accepted", "version"],
    "forbidden_client_fields": ["ownerId", "model", "max_tokens", "systemPrompt",
                                "providerUrl", "apiKey", "stream", "thinking"],
}
HTTP_ERROR_CODES = {"invalidInput", "inputTooLong", "unauthorized", "consentRequired",
                    "rateLimited", "providerUnavailable", "invalidOutput", "timeout", "unexpected"}
# section -> (required keys, optional keys, allowed verdicts)
SECTIONS = {
    "request_cases": ("id expect body", "error_code normalized_inputs interpretation", "accepted rejected"),
    "transport_cases": ("id expect", "error_code generator body require_multibyte_bytes_gt_chars interpretation", "accepted rejected"),
    "provider_cases": ("id expect stage provider", "reason normalized_summary interpretation", "accepted rejected"),
    "response_cases": ("id expect envelope", "reason interpretation", "accepted rejected"),
    "token_boundary_cases": ("id expect measure", "synthetic_total_input_tokens synthetic_content_tokens synthetic_prompt_tokens interpretation", "within_budget over_budget"),
    "pipeline_cases": ("id expect stage_plan expect_calls", "interpretation", "allowed pipelineTooLarge"),
    "negative_self_checks": ("id kind case_id", "key value interpretation", "flip_expect drop_key add_key"),
}
REQUIRED_CASE_KEYS = {name: set(required.split()) for name, (required, _, _) in SECTIONS.items()}
CASE_KEYS = {name: REQUIRED_CASE_KEYS[name] | set(optional.split()) for name, (_, optional, _) in SECTIONS.items()}
VERDICTS = {name: set(verdicts.split()) for name, (_, _, verdicts) in SECTIONS.items()}
TOP_LEVEL_KEYS = {"fixture_meta", "contract_decisions", *SECTIONS}
ACCEPTING = {"accepted", "within_budget", "allowed"}


class Report:
    def __init__(self, name):
        self.name, self.checked, self.problems, self.notes = name, 0, [], []

    def case(self):
        self.checked += 1

    def bad(self, case_id, message):
        self.problems.append(f"[{self.name}] {case_id}: {message}")


def text_ok(value):
    return isinstance(value, str) and bool(value.strip())


def usage_ok(usage):
    return (isinstance(usage, dict) and set(usage) == {"inputTokens", "outputTokens"}
            and all(type(usage[key]) is int and usage[key] >= 0 for key in usage))


def locate(doc, case_id):
    for section in SECTIONS:
        for case in doc.get(section) or []:
            if isinstance(case, dict) and case.get("id") == case_id:
                return case
    return None


def mismatch(case, ok, code):
    """Return None when the fixture declaration and the oracle verdict agree."""
    declared = case.get("error_code") or case.get("reason") or case["expect"]
    if case["expect"] in ACCEPTING:
        return None if ok else f"declared {case['expect']} but oracle rejected ({code})"
    if ok:
        return f"declared {case['expect']} but oracle accepted"
    return None if declared == code else f"declared {declared} but oracle reported {code}"


def body_bytes(body):
    return len(json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))


def pad_ascii(body, path, target):
    node = body
    for key in path[:-1]:
        node = node[key]
    leaf = path[-1]
    node[leaf] = str(node[leaf]) + "a"
    for _ in range(12):
        delta = target - body_bytes(body)
        if delta == 0:
            break
        node[leaf] = node[leaf] + "a" * delta if delta > 0 else node[leaf][:delta]
    return body_bytes(body)


def oracle_request(body):
    """Fixture-only mirror of the contract request rules (sections 2-3)."""
    if not isinstance(body, dict) or set(body) - set(FROZEN["request_allowed_fields"]):
        return False, "invalidInput", None
    stage, inputs = body.get("stage"), body.get("inputs")
    if not isinstance(stage, str) or stage not in FROZEN["stages"]:
        return False, "invalidInput", None
    if not isinstance(inputs, list) or any(type(item) is not str for item in inputs):
        return False, "invalidInput", None
    low, high = FROZEN["stage_input_cardinality"][stage]
    normalized = [item.strip() for item in inputs]
    if not low <= len(inputs) <= high or not all(normalized):
        return False, "invalidInput", None
    consent = body.get("consent")
    if not isinstance(consent, dict):
        return False, "consentRequired", None
    if set(consent) - set(FROZEN["consent_allowed_fields"]):
        return False, "invalidInput", None
    if consent.get("accepted") is not True or consent.get("version") != FROZEN["consent_version"]:
        return False, "consentRequired", None
    return True, None, normalized


def oracle_provider(provider, stage):
    if not isinstance(provider, dict) or set(provider) - {"finish_reason", "text", "usage"}:
        return False, "provider_schema"
    reason = provider.get("finish_reason")
    if not isinstance(reason, str):
        return False, "missing_finish_reason"
    if reason != "stop":
        return False, reason
    if not text_ok(provider.get("text")):
        return False, "empty_output"
    usage = provider.get("usage")
    if not isinstance(usage, dict):
        return False, "usage_missing"
    if not usage_ok(usage):
        return False, "usage_shape"
    if usage["outputTokens"] > FROZEN["max_output_tokens"][stage]:
        return False, "budget_mismatch"
    return True, None


def oracle_response(envelope):
    if not isinstance(envelope, dict):
        return False, "safe_fallback"
    if "error" in envelope:
        error = envelope.get("error")
        if not isinstance(error, dict) or set(error) != {"code"} or set(envelope) - {"error", "requestId"}:
            return False, "error_shape"
        code = error["code"]
        if not isinstance(code, str) or code not in HTTP_ERROR_CODES:
            return False, "unknown_error_code"
        return (True, None) if text_ok(envelope.get("requestId")) else (False, "error_shape")
    if set(envelope) != {"summary", "requestId", "usage"}:
        return False, "response_shape"
    if not text_ok(envelope["summary"]) or not text_ok(envelope["requestId"]):
        return False, "response_shape"
    return (True, None) if usage_ok(envelope["usage"]) else (False, "response_shape")


def oracle_request_case(case):
    ok, code, normalized = oracle_request(case["body"])
    if ok and "normalized_inputs" in case and normalized != case["normalized_inputs"]:
        return False, "normalized_inputs_mismatch"
    return ok, code


def oracle_transport_case(case):
    if ("generator" in case) == ("body" in case):
        return False, "fixture_needs_one_body_source"
    if "generator" in case:
        spec = case["generator"]
        if spec.get("kind") != "pad_ascii" or spec.get("path") != ["inputs", 0]:
            return False, "unsupported_generator"
        body = deepcopy(spec["base_body"])
        size = pad_ascii(body, spec["path"], spec["target_body_bytes"])
        if size != spec["target_body_bytes"]:
            return False, "generator_size_mismatch"
    else:
        body, size = case["body"], body_bytes(case["body"])
    if case.get("require_multibyte_bytes_gt_chars"):
        chars = len(json.dumps(body, separators=(",", ":"), ensure_ascii=False))
        if size <= chars:
            return False, "multibyte_bytes_not_greater_than_chars"
    ok, code, _ = oracle_request(body)
    cap = FROZEN["max_body_bytes_utf8"]
    if ok and size > cap:
        return False, "inputTooLong"
    if not ok and code == "inputTooLong" and size <= cap:
        return False, "inputTooLong_declared_within_cap"
    return ok, code


def oracle_provider_case(case):
    if case["stage"] not in FROZEN["stages"]:
        return False, "unknown_stage"
    ok, code = oracle_provider(case["provider"], case["stage"])
    if ok and "normalized_summary" in case and case["provider"]["text"].strip() != case["normalized_summary"]:
        return False, "normalized_summary_mismatch"
    return ok, code


def oracle_tokens(case):
    if case.get("measure") != "synthetic":
        return False, "missing_synthetic_label"
    parts = [case[key] for key in ("synthetic_content_tokens", "synthetic_prompt_tokens") if key in case]
    total = case.get("synthetic_total_input_tokens")
    if any(type(value) is not int or value < 0 for value in parts):
        return False, "token_value_invalid"
    if total is not None and (type(total) is not int or total < 0):
        return False, "token_value_invalid"
    if parts and total is not None and total != sum(parts):
        return False, f"parts_sum_mismatch({sum(parts)})"
    total = sum(parts) if parts and total is None else total
    if type(total) is not int or total < 0:
        return False, "token_value_invalid"
    return (False, "over_budget") if total > FROZEN["max_input_tokens_per_call"] else (True, None)


def oracle_pipeline(case):
    """Blocked plans report 0 generation calls; allowed plans 1 or sections + one merge."""
    plan = case["stage_plan"]
    low, high = FROZEN["chunk_count_range"]
    valid = isinstance(plan, list) and bool(plan) and all(stage in FROZEN["stages"] for stage in plan)
    sections = plan.count("section") if valid else 0
    merges = plan.count("merge") if valid else 0
    allowed = valid and ("direct" not in plan or plan == ["direct"])
    if allowed and plan != ["direct"]:
        allowed = low <= sections <= high and merges == FROZEN["merge_calls_per_pipeline"] and plan[-1] == "merge"
    calls = (1 if plan == ["direct"] else sections + merges) if allowed else 0
    if calls > FROZEN["max_generation_calls"]:
        allowed, calls = False, 0
    if calls != case["expect_calls"]:
        return False, f"call_count_mismatch({calls})"
    return (True, None) if allowed else (False, "pipelineTooLarge")


CASE_ORACLES = {"request_cases": oracle_request_case, "transport_cases": oracle_transport_case,
                "provider_cases": oracle_provider_case,
                "response_cases": lambda case: oracle_response(case["envelope"]),
                "token_boundary_cases": oracle_tokens, "pipeline_cases": oracle_pipeline}


def check_shape(doc):
    """Default checking fails on unexpected schema or a malformed fixture."""
    rep = Report("shape")
    rep.case()
    if not isinstance(doc, dict):
        rep.bad("<file>", "fixtures must be a JSON object")
        return rep
    for key in sorted(set(doc) ^ TOP_LEVEL_KEYS):
        rep.bad("<file>", f"{'unexpected' if key in doc else 'missing'} top-level key {key!r}")
    seen = {}
    for section, allowed in CASE_KEYS.items():
        rows = doc.get(section)
        if not isinstance(rows, list) or not rows:
            rep.bad(section, "section must be a non-empty array")
            continue
        for index, case in enumerate(rows):
            where = f"{section}[{index}]"
            if not isinstance(case, dict):
                rep.bad(where, "case must be a JSON object")
                continue
            cid = case.get("id") if text_ok(case.get("id")) else where
            if cid is where:
                rep.bad(where, "case needs a non-empty string 'id'")
            elif cid in seen:
                rep.bad(cid, f"duplicate case id (also in {seen[cid]})")
            else:
                seen[cid] = section
            for key in sorted(set(case) - allowed):
                rep.bad(cid, f"unexpected case key {key!r}")
            for key in sorted(REQUIRED_CASE_KEYS[section] - set(case)):
                rep.bad(cid, f"missing required case key {key!r}")
            field = "kind" if section == "negative_self_checks" else "expect"
            if case.get(field) not in VERDICTS[section]:
                rep.bad(cid, f"{field} must be one of {sorted(VERDICTS[section])}")
    return rep


def check_decisions(doc):
    rep = Report("decisions")
    rep.case()
    declared = doc.get("contract_decisions")
    if not isinstance(declared, dict):
        rep.bad("contract_decisions", "must be a JSON object")
        return rep
    for key in sorted(FROZEN):
        if key not in declared:
            rep.bad("contract_decisions", f"missing frozen key {key!r}")
        elif type(declared[key]) is not type(FROZEN[key]) or declared[key] != FROZEN[key]:
            rep.bad("contract_decisions", f"{key}: fixture {declared[key]!r} != frozen {FROZEN[key]!r}")
    for key in sorted(set(declared) - set(FROZEN)):
        rep.bad("contract_decisions", f"unexpected key {key!r} (not a frozen decision)")
    return rep


def check_cases(doc):
    """One loop for all six case sections; each oracle owns its section rules."""
    reports = []
    for section, oracle in CASE_ORACLES.items():
        rep = Report(section.split("_")[0])
        for case in doc[section]:
            rep.case()
            message = mismatch(case, *oracle(case))
            if message:
                rep.bad(case["id"], message)
        reports.append(rep)
    return reports


def check_self_checks(doc):
    """Deliberate-negative self-check: mutations must be caught by the same oracles."""
    rep = Report("self-check")
    for spec in doc["negative_self_checks"]:
        rep.case()
        if locate(doc, spec["case_id"]) is None:
            rep.bad(spec["id"], f"self-check target {spec['case_id']!r} not found")
            continue
        mutated = deepcopy(doc)
        twin = locate(mutated, spec["case_id"])
        if spec["kind"] == "flip_expect":
            twin["expect"] = "rejected" if twin["expect"] == "accepted" else "accepted"
        elif spec["kind"] == "drop_key":
            twin.pop(spec["key"], None)
        else:
            twin[spec["key"]] = spec.get("value")
        found = [p for report in check_fixture(mutated, with_self_checks=False) for p in report.problems]
        if found:
            rep.notes.append(f"{spec['id']}: {spec['kind']} detected via {found[0]}")
        else:
            rep.bad(spec["id"], f"{spec['kind']} mutation was NOT detected")
    return rep


def check_fixture(doc, with_self_checks=True):
    shape = check_shape(doc)
    if shape.problems:
        return [shape]
    reports = [shape, check_decisions(doc), *check_cases(doc)]
    if with_self_checks:
        reports.append(check_self_checks(doc))
    return reports


def main(argv):
    path = Path(argv[1]).resolve() if len(argv) > 1 else FIXTURES_PATH
    if not path.is_file():
        print(f"FAIL: fixture file not found: {path}", file=sys.stderr)
        return 2
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"FAIL: cannot load {path}: {exc}", file=sys.stderr)
        return 2
    print(f"fixtures: {path}")
    print("oracle: frozen Phase 1 decisions; token fixtures are synthetic, not measured tokens")
    reports = check_fixture(doc)
    for report in reports:
        print(f"  {report.name:<10} cases={report.checked:<3} problems={len(report.problems)}")
    for note in reports[-1].notes:
        print(f"  negative self-check -> {note}")
    problems = [problem for report in reports for problem in report.problems]
    if problems:
        print(f"\nFAIL: {len(problems)} problem(s)")
        for problem in problems:
            print(f"  {problem}")
        return 1
    print(f"\nPASS: {sum(report.checked for report in reports)} fixture cases consistent "
          "with the frozen contract decisions")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
