#!/usr/bin/env python3
"""Check synthetic note assets only; no model, tokenization or product evidence."""

import json
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent


def check(doc, matrix):
    assert set(doc) == {"schemaVersion", "synthetic", "cases"}, "top-level schema"
    assert type(doc["schemaVersion"]) is int and doc["schemaVersion"] == 1, "version"
    assert doc["synthetic"] is True, "synthetic label"
    cases = doc["cases"]
    assert isinstance(cases, list) and len(cases) == 10, "exactly 10 cases required"
    assert len({c["id"] for c in cases}) == 10, "unique IDs required"
    assert Counter(c["group"] for c in cases) == dict.fromkeys(
        ("vi_en", "mixed_injection", "empty_oversize", "consent_account", "provider_failure"), 2
    ), "five groups of two"
    required = {"id", "group", "title", "scenario", "expectedStagePlan",
                "expectedGenerationCalls", "outcomeKind", "expectedOutcome",
                "expectedFacts", "forbiddenClaims"}
    optional = {"content", "contentDescriptor", "expectedStageRequests", "variants"}
    for case in cases:
        cid = case.get("id", "<missing>")
        assert required <= set(case) <= required | optional, f"{cid}: case schema"
        for key in ("id", "group", "title", "scenario", "outcomeKind", "expectedOutcome"):
            assert isinstance(case[key], str) and case[key].strip(), f"{cid}: {key}"
        assert cid in matrix, f"{cid}: missing matrix mapping"
        for key in ("expectedFacts", "forbiddenClaims"):
            value = case[key]
            assert isinstance(value, list) and value, f"{cid}: {key}"
            assert all(isinstance(v, str) and v.strip() for v in value), f"{cid}: {key} text"
        content = case.get("content", "")
        assert isinstance(content, str), f"{cid}: content type"
        plan, calls = case["expectedStagePlan"], case["expectedGenerationCalls"]
        assert isinstance(plan, list) and type(calls) is int, f"{cid}: plan/calls type"
        kind = case["outcomeKind"]
        if kind == "blocked_before_request":
            assert plan == [] and calls == 0, f"{cid}: blocked plan"
        elif kind == "summary_direct":
            assert content.strip() and plan == ["direct"] and calls == 1, f"{cid}: direct plan"
        else:
            assert kind == "atomic_stop_preserve_state", f"{cid}: outcome kind"
            assert 3 <= len(plan) <= 5 and plan == ["section"] * (len(plan) - 1) + ["merge"], f"{cid}: long plan"
            assert 1 <= calls < len(plan), f"{cid}: stop before full plan completes"
        if "expectedStageRequests" in case:
            requests = case["expectedStageRequests"]
            assert type(requests) is int and calls <= requests <= len(plan), f"{cid}: HTTP count"
        variants = case.get("variants", [])
        assert isinstance(variants, list), f"{cid}: variants array"
        assert len({v["name"] for v in variants}) == len(variants), f"{cid}: unique variants"
        for value in variants:
            assert set(value) == {"name", "scenario", "expectedStageRequests",
                                  "expectedGenerationCalls", "expectedOutcome"}, f"{cid}: variant schema"
            for key in ("name", "scenario", "expectedOutcome"):
                assert isinstance(value[key], str) and value[key].strip(), f"{cid}: variant {key}"
            requests, generations = value["expectedStageRequests"], value["expectedGenerationCalls"]
            assert type(requests) is int and 0 <= requests <= 5, f"{cid}: variant HTTP count"
            assert generations is None or (type(generations) is int and 0 <= generations <= requests), f"{cid}: variant generation count"
            if generations is None:
                assert value["name"] == "timeout_after_dispatch", f"{cid}: unknown billing only for dispatched timeout"
        desc = case.get("contentDescriptor")
        if desc is None:
            continue
        if desc["kind"] == "empty_after_trim":
            assert content == desc["raw"] and not content.strip(), f"{cid}: empty descriptor"
            assert len(content) == desc["rawChars"] and desc["charsAfterTrim"] == 0, f"{cid}: empty size"
            continue
        assert desc["kind"] == "repeat_unit", f"{cid}: descriptor kind"
        count, unit = desc["repeatCount"], desc["unit"]
        assert type(count) is int and 0 < count <= 10000 and isinstance(unit, str), f"{cid}: repeat"
        assert len(unit) == desc["unitChars"] and len(unit.encode()) == desc["unitUtf8Bytes"], f"{cid}: unit size"
        expanded = content + unit * count
        assert len(expanded) == desc["expandedChars"], f"{cid}: expanded chars"
        assert len(expanded.encode()) == desc["expandedUtf8Bytes"], f"{cid}: expanded bytes"
        assert desc["blobStoredInFixture"] is False, f"{cid}: blob label"
        budget = desc["tokenBudgetCheck"]
        keys = ("simulatedContentTokens", "simulatedPromptTokensPerCall", "simulatedTotalInputTokens")
        assert all(type(budget[k]) is int and budget[k] >= 0 for k in keys), f"{cid}: synthetic integers"
        tokens, prompt, total = (budget[k] for k in keys)
        assert budget["maxInputTokensPerCall"] == 16000 and budget["maxChunks"] == 4, f"{cid}: budgets"
        assert total == tokens + prompt and prompt < 16000, f"{cid}: synthetic total"
        chunks = (tokens + (16000 - prompt) - 1) // (16000 - prompt)
        assert chunks == budget["minimalChunksAtThisBudget"], f"{cid}: synthetic chunk count"
        assert budget["trips"] is (total > 16000), f"{cid}: synthetic cap flag"
        if kind == "blocked_before_request":
            assert chunks > 4, f"{cid}: oversize must exceed pipeline cap"
        else:
            assert chunks == plan.count("section"), f"{cid}: sections vs synthetic count"
        size = desc["bodyBytesCheck"]
        assert size["capUtf8Bytes"] == 262144 and size["jsonWrapperIncluded"] is False, f"{cid}: byte scope"
        assert size["expandedNoteUtf8Bytes"] == len(expanded.encode()), f"{cid}: byte metadata"
        body = {"stage": "section", "inputs": [expanded],
                "consent": {"accepted": True, "version": "summary-cloud-v1"}}
        body_bytes = len(json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode())
        assert size["trips"] is (body_bytes > 262144), f"{cid}: transport flag including wrapper"
    return len(cases)


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "note_fixtures.json"
    try:
        count = check(json.loads(path.read_text(encoding="utf-8")),
                      (HERE / "acceptance_matrix.md").read_text(encoding="utf-8"))
    except (AssertionError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(f"PASS: {count} synthetic note assets, descriptor sizes, simulated plans and matrix IDs")
    print("Asset evidence only: no model generation, real token count or runtime verification.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
