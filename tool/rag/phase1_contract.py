"""Offline Phase-1 fixture oracle. Not a JWT verifier, tokenizer or RAG runtime."""
import json
import math
import re
from fractions import Fraction


class ContractError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ContractError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def load_json(text):
    def invalid_constant(value):
        raise ContractError("non-finite JSON constant")
    return json.loads(text, object_pairs_hook=unique_object,
                      parse_constant=invalid_constant)


def exact_keys(value, required, optional=()):
    require(type(value) is dict, "expected object")
    require(set(required) <= value.keys(), "missing field")
    require(value.keys() <= set(required) | set(optional), "unknown field")


def whole(value, minimum=0):
    return (type(value) in (int, float) and minimum <= value <= 9007199254740991
            and value == int(value))


def identifier(value):
    return (type(value) is str and 0 < len(value) <= 128
            and value == value.strip()
            and not re.search(r"[\x00-\x1f\x7f]", value))


def utf8_size(value):
    try:
        return len(value.encode("utf-8"))
    except UnicodeError as error:
        raise ContractError("invalid Unicode") from error


def source_slice(text, start, end):
    require(whole(start) and whole(end) and start < end, "invalid source span")
    start, end = int(start), int(end)
    encoded = text.encode("utf-16-le")
    require(end * 2 <= len(encoded), "source span outside text")
    try:
        return encoded[start * 2:end * 2].decode("utf-16-le")
    except UnicodeError as error:
        raise ContractError("source span bisects surrogate") from error


def validate_request(value, policy):
    exact_keys(value, ("wireVersion", "question", "scope"))
    require(whole(value["wireVersion"], 1) and value["wireVersion"] == 1,
            "invalid wire version")
    question = value["question"]
    require(type(question) is str and bool(question.strip()), "empty question")
    limits = policy["technicalDefaults"]["wire"]
    require(len(question) <= limits["questionMaxCodePoints"], "question too long")
    require(utf8_size(question) <= limits["questionMaxUtf8Bytes"], "question too large")
    scope = value["scope"]
    require(type(scope) is dict, "invalid scope")
    if scope.get("type") == "account":
        exact_keys(scope, ("type",))
    else:
        exact_keys(scope, ("type", "noteId"))
        require(scope["type"] == "note" and identifier(scope["noteId"]), "invalid scope")
    size = utf8_size(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
    require(size <= limits["bodyMaxUtf8Bytes"], "body too large")


def eligible(note, actor):
    """Simulates already-resolved canonical facts; never accepts client proof."""
    return (identifier(actor) and note.get("ownerId") == actor
            and note.get("synced") is True and note.get("protected") is False
            and note.get("deleted") is False and note.get("available") is True
            and whole(note.get("revision"), 1))


def authorize_fixture(case, notes):
    require(case["authenticated"] is True, "UNAUTHORIZED")
    actor = case["actorId"]
    require(identifier(actor), "UNAUTHORIZED")
    consent = case["consent"]
    require(whole(consent["generation"]) and whole(case["capturedConsentGeneration"]),
            "CONSENT_REQUIRED")
    require(consent["accepted"] is True and consent["version"] == "rag-consent.v1",
            "CONSENT_REQUIRED")
    require(consent["generation"] == case["capturedConsentGeneration"], "CONSENT_REQUIRED")
    require(whole(case["sessionGeneration"]) and whole(case["capturedSessionGeneration"])
            and case["sessionGeneration"] == case["capturedSessionGeneration"], "SOURCE_CHANGED")
    require(case["indexState"] == "READY", "INDEX_NOT_READY")
    wanted = case["request"]["scope"]
    if wanted["type"] == "note":
        matches = [n for n in notes.values()
                   if n["noteId"] == wanted["noteId"] and eligible(n, actor)]
        require(bool(matches), "SCOPE_DENIED")
    for source_id in case["evidenceIds"]:
        source = case["sourceMap"][source_id]
        note = notes[source["fixtureNoteKey"]]
        require(eligible(note, actor), "SCOPE_DENIED")
        require(wanted["type"] == "account" or note["noteId"] == wanted["noteId"],
                "SCOPE_DENIED")
        require(source["revision"] == note["revision"], "SOURCE_CHANGED")
        require(source_slice(note["content"], source["startOffset"], source["endOffset"])
                == source["quote"], "SOURCE_CHANGED")


def validate_noul_envelope(value):
    exact_keys(value, ("model", "answers", "usage"))
    require(identifier(value["model"]), "invalid model")
    ids = ("answerable_from_evidence", "has_unresolved_conflict")
    exact_keys(value["answers"], ids)
    for question_id in ids:
        answer = value["answers"][question_id]
        exact_keys(answer, ("type", "noul"))
        p = answer["noul"]
        require(answer["type"] == "noul" and type(p) in (int, float)
                and math.isfinite(p) and 0 <= p <= 1, "invalid Noul answer")
    exact_keys(value["usage"], ("input_tokens", "output_tokens"))
    require(all(whole(x) for x in value["usage"].values()), "invalid usage")


def mock_decision(value, thresholds):
    """Threshold values here are fixture-only, never provider calibration."""
    if thresholds is None:
        return "ERROR", "LIVE_POLICY_NOT_CONFIGURED"
    exact_keys(thresholds, ("answerabilityMin", "conflictMax"))
    require(all(type(v) in (int, float) and math.isfinite(v)
                for v in thresholds.values()), "invalid mock thresholds")
    try:
        validate_noul_envelope(value)
    except (ContractError, TypeError, KeyError):
        return "ERROR", "EVIDENCE_VALIDATION_UNAVAILABLE"
    support = value["answers"]["answerable_from_evidence"]["noul"]
    conflict = value["answers"]["has_unresolved_conflict"]["noul"]
    high, low = thresholds["answerabilityMin"], thresholds["conflictMax"]
    require(0.5 < high <= 1 and 0 <= low < 0.5, "invalid mock thresholds")
    if conflict >= high:
        return "NOT_ENOUGH_CONTEXT", "UNRESOLVED_CONFLICT"
    if support <= low:
        return "NOT_ENOUGH_CONTEXT", "INSUFFICIENT_EVIDENCE"
    if support < high or conflict > low:
        return "NOT_ENOUGH_CONTEXT", "UNCERTAIN"
    return "ANSWER_ALLOWED", None


def rrf_order(rankings, constant=60):
    require(type(constant) is int and constant > 0, "invalid RRF constant")
    scores = {}
    for values in rankings:
        seen = set()
        for rank, key in enumerate(values, 1):
            require(identifier(key), "invalid candidate key")
            if key in seen:
                continue
            seen.add(key)
            scores[key] = scores.get(key, Fraction(0)) + Fraction(1, constant + rank)
    return sorted(scores, key=lambda key: (-scores[key], key))


def merge_ranges(spans):
    groups = {}
    for span in spans:
        exact_keys(span, ("ownerId", "noteId", "revision", "sectionId", "startOffset", "endOffset"))
        require(all(identifier(span[k]) for k in ("ownerId", "noteId", "sectionId")), "invalid identity")
        require(whole(span["revision"], 1), "invalid revision")
        start, end = span["startOffset"], span["endOffset"]
        require(whole(start) and whole(end) and start < end, "invalid span")
        identity = tuple(span[k] for k in ("ownerId", "noteId", "revision", "sectionId"))
        groups.setdefault(identity, []).append((start, end))
    result = []
    for identity, values in sorted(groups.items()):
        merged = []
        for start, end in sorted(values):
            if merged and start <= merged[-1][1]:
                merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
            else:
                merged.append((start, end))
        for start, end in merged:
            result.append(dict(zip(("ownerId", "noteId", "revision", "sectionId",
                                    "startOffset", "endOffset"), (*identity, start, end))))
    return result


def validate_response(value, case, notes, policy):
    common = ("wireVersion", "requestId", "status")
    require(type(value) is dict and whole(value.get("wireVersion"), 1)
            and value["wireVersion"] == 1 and identifier(value.get("requestId")), "invalid response")
    status = value["status"]
    if status == "ERROR":
        exact_keys(value, (*common, "code"))
        require(type(value["code"]) is str and
                value["code"] in policy["technicalDefaults"]["errorHttpStatus"], "unknown error")
    elif status == "NOT_ENOUGH_CONTEXT":
        exact_keys(value, (*common, "reason", "answer", "sources"))
        require(value["answer"] is None and value["sources"] == [], "abstention has answer")
        require(value["reason"] in ("INSUFFICIENT_EVIDENCE", "UNRESOLVED_CONFLICT", "UNCERTAIN"),
                "invalid abstention reason")
    else:
        authorize_fixture(case, notes)
        exact_keys(value, (*common, "answer", "sources"))
        require(status == "ANSWERED" and type(value["answer"]) is str
                and bool(value["answer"].strip()), "invalid answer")
        sources = value["sources"]
        require(type(sources) is list and 0 < len(sources) <= 24, "invalid sources")
        used = set()
        for source in sources:
            exact_keys(source, ("sourceId", "noteId", "revision", "title",
                               "startOffset", "endOffset", "quote"))
            source_id = source["sourceId"]
            require(identifier(source_id) and source_id not in used
                    and source_id in case["evidenceIds"], "unknown/duplicate citation")
            used.add(source_id)
            expected = case["sourceMap"][source_id]
            note = notes[expected["fixtureNoteKey"]]
            require(eligible(note, case["actorId"]), "citation outside scope")
            for key in ("noteId", "revision", "startOffset", "endOffset", "quote"):
                numeric = key in ("revision", "startOffset", "endOffset")
                typed = whole(source[key]) if numeric else type(source[key]) is type(expected[key])
                require(typed and source[key] == expected[key],
                        "citation lineage mismatch")
            require(source["revision"] == note["revision"] and source["title"] == note["title"],
                    "citation stale")
            require(source_slice(note["content"], source["startOffset"], source["endOffset"])
                    == source["quote"], "citation span mismatch")
        referenced = set(re.findall(r"\[(S[1-9][0-9]*)\]", value["answer"]))
        require(bool(referenced) and referenced == used, "answer/source labels mismatch")
    require(utf8_size(json.dumps(value, ensure_ascii=False))
            <= policy["technicalDefaults"]["wire"]["responseMaxUtf8Bytes"], "response too large")
