"""Read-only stdlib checker for RAG Phase-1 artifacts, not deployed behavior."""
import argparse
from pathlib import Path
from phase1_contract import (ContractError, authorize_fixture, eligible, load_json,
                             merge_ranges, mock_decision, require, rrf_order,
                             source_slice, validate_noul_envelope, validate_request,
                             validate_response, whole)


def read(root, relative):
    return load_json((root / relative).read_text(encoding="utf-8"))


def check_policy(p):
    require(p["runtimeEnabled"] is False, "Phase 1 must not enable runtime")
    scope = p["approvedScope"]
    require(scope == dict(ownership="own", syncedOnly=True, textOnly=True,
                         protectedAllowed=False, sharedAllowed=False,
                         attachmentsAllowed=False, turns=1, scopeTypes=["account", "note"]),
            "approved scope drift")
    require(p["chunking"]["targetTokens"] == 400 and p["chunking"]["maxEmbeddingTokens"] == 512
            and p["chunking"]["overlapTokens"] == 0, "chunk policy drift")
    require(p["embedding"] == dict(model="cohere.embed-multilingual-v3", dimensions=1024,
                                   documentInputType="search_document",
                                   queryInputType="search_query", truncate="NONE"), "embedding drift")
    r = p["retrieval"]
    require((r["vectorTopK"], r["bm25TopK"], r["maxUnionCandidates"]) == (20, 20, 40),
            "Top-K drift")
    require(r["rrf"] == dict(constant=60, vectorWeight=1, bm25Weight=1, rankStartsAt=1),
            "RRF drift")
    require(r["mmr"]["lambda"] == 0.7 and r["mmr"]["maxAnchors"] == 8, "MMR drift")
    c = p["context"]
    require((c["previousChunks"], c["nextChunks"], c["evidenceMaxTokens"]) == (1, 1, 6000)
            and c["recursive"] is False and c["semanticDedupe"] is False
            and c["anchorsFirst"] is True and c["removeExpansionFirst"] is True,
            "context drift")
    require(set(p["jev"]["questions"]) == {"answerable_from_evidence", "has_unresolved_conflict"},
            "Jev question IDs drift")
    for q in p["jev"]["questions"].values():
        require(q["type"] == "noul" and set(q["criteria"]) == {"true", "false"}, "Noul drift")
    criteria = {
        "answerable_from_evidence": {
            "true": "Evidence có dữ kiện cho các phần user hỏi, đúng đối tượng và điều kiện liên quan.",
            "false": "Chỉ cùng chủ đề; thiếu dữ kiện; hoặc phải bổ sung kiến thức ngoài evidence."},
        "has_unresolved_conflict": {
            "true": "Cùng đối tượng/điều kiện nhưng có thông tin không tương thích, context chưa giải quyết.",
            "false": "Không có mâu thuẫn liên quan hoặc evidence giải thích rõ sự khác biệt."}}
    require(p["jev"]["questionSetVersion"] == "rag-evidence.v1", "question version drift")
    require(all(p["jev"]["questions"][key]["criteria"] == value
                for key, value in criteria.items()), "approved criteria drift")
    require(p["jev"]["liveThresholds"] is None and p["jev"]["liveModel"] is None,
            "uncalibrated live policy")
    require(p["mockOnly"]["provenance"] == "synthetic-fixture-values-not-calibrated",
            "mock values misrepresented")
    require(p["safety"]["automaticRetrievalLoop"] is False
            and p["safety"]["automaticGenerationRetry"] is False, "hidden retry policy")
    require(p["technicalDefaults"]["approval"] == "PROPOSED_FOR_CONTRACT_REVIEW",
            "technical defaults marked approved")


def outcome(case, notes, policy):
    validate_request(case["request"], policy)
    try:
        authorize_fixture(case, notes)
    except ContractError as error:
        return "ERROR", str(error)
    if not case["evidenceIds"]:
        return "NOT_ENOUGH_CONTEXT", "INSUFFICIENT_EVIDENCE"
    mock = case["providerMock"]
    if mock["errorCode"]:
        return "ERROR", mock["errorCode"]
    return mock_decision(mock["jev"], policy["mockOnly"]["thresholds"])


def expect_validation(case, operation):
    try:
        operation(case["payload"])
        valid = True
    except (ContractError, ValueError, TypeError, KeyError):
        valid = False
    require(valid is case["valid"], "wire expectation mismatch: " + case["id"])


def verify(root):
    policy = read(root, "docs/rag/policy_v1.json")
    check_policy(policy)
    registry = read(root, "docs/rag/contract_registry.json")
    ids = [r["id"] for r in registry["contracts"]]
    require(len(set(ids)) == 25 and set(ids) == {f"C{i:02}" for i in range(1, 26)},
            "registry incomplete")
    require(registry["scopeDecision"]["status"] == "APPROVED_BY_USER"
            and registry["scopeDecision"]["scope"] == policy["approvedScope"], "scope mismatch")
    require(all(r["runtimeVerification"] == "UNVERIFIED" for r in registry["contracts"]),
            "runtime gate falsely closed")
    notes_doc = read(root, "test/fixtures/rag/notes.json")
    notes = {n["key"]: n for n in notes_doc["notes"]}
    require(len(notes) == len(notes_doc["notes"]), "duplicate fixture note key")
    cases_doc = read(root, "test/fixtures/rag/query_cases.json")
    cases = {c["id"]: c for c in cases_doc["cases"]}
    require(len(cases) == 24 and {c["language"] for c in cases.values()} == {"vi", "en"},
            "gold cases missing")
    for case in cases.values():
        actual = outcome(case, notes, policy)
        expected = case["expected"]
        require(actual == (expected["status"], expected["reason"]), "query mismatch: " + case["id"])
        simulated_calls = int(actual[0] == "ANSWER_ALLOWED")
        require(simulated_calls == expected["expectedDeepseekCalls"], "generation branch mismatch")
        require(set(expected["goldSourceIds"]) <= set(case["evidenceIds"]), "gold source unknown")
    require(not eligible(notes["a-local"], "actor-a") and not eligible(notes["a-protected"], "actor-a")
            and not eligible(notes["a-deleted"], "actor-a")
            and not eligible(notes["b-watch"], "actor-a"), "eligibility gap")
    wire = read(root, "test/fixtures/rag/wire_cases.json")
    for case in wire["requests"]:
        expect_validation(case, lambda value: validate_request(value, policy))
    for case in wire["responses"]:
        expect_validation(case, lambda value: validate_response(value, cases[case["caseId"]], notes, policy))
    for case in wire["nouls"]:
        expect_validation(case, validate_noul_envelope)
    ranking = read(root, "test/fixtures/rag/ranking_cases.json")
    for case in ranking["cases"]:
        require(rrf_order(case["rankings"]) == case["expected"], "ranking mismatch")
    context = read(root, "test/fixtures/rag/context_cases.json")
    for case in context["cases"]:
        require(merge_ranges(case["spans"]) == case["expected"], "dedupe mismatch")
    for case in context["budgetCases"]:
        limit = policy["chunking"]["maxEmbeddingTokens"] if case["kind"] == "embedding" else 6000
        valid = whole(case["tokens"], 1) and case["tokens"] <= limit
        if case["kind"] == "embedding":
            valid = valid and whole(case["characters"], 1) and case["characters"] <= 2048
        require(valid is case["valid"], "injected budget mismatch")
    unicode_note = notes["a-unicode"]["content"]
    require(source_slice(unicode_note, 0, 2) == "🧠", "UTF-16 source offsets")
    artifact_paths = ("docs/contracts/rag_api_v1.md", "docs/rag/contract_registry.md",
                      "docs/rag/acceptance_matrix.md", "docs/rag/open_decisions.md")
    for path in artifact_paths:
        text = (root / path).read_text(encoding="utf-8")
        require(bool(text.strip()), "empty artifact")
    matrix = (root / "docs/rag/acceptance_matrix.md").read_text(encoding="utf-8")
    require(all(x in matrix for x in ids), "contract missing from acceptance matrix")
    all_cases = [*cases.values(), *wire["requests"], *wire["responses"], *wire["nouls"],
                 *ranking["cases"], *context["cases"], *context["budgetCases"]]
    require(all(set(c["contracts"]) <= set(ids) for c in all_cases), "unknown contract ref")
    return dict(notes=len(notes), query_cases=len(cases), wire_cases=sum(len(wire[k])
                for k in ("requests", "responses", "nouls")), ranking_cases=len(ranking["cases"]),
                source_span_cases=len(context["cases"]), synthetic_budget_cases=len(context["budgetCases"]),
                contract_rows=len(ids), runtime_verified=False, provider_calls=0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    result = verify(args.root)
    print("PASS — Phase 1 offline artifact/fixture checks")
    import json
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
