/// Provider-neutral Domain contract for one RAG (ask-my-notes) interaction.
///
/// Pure Dart: this library never imports Application, Flutter, a provider SDK,
/// or a transport, and it never carries a token, an actor header, or a wire
/// envelope. [RagCallContext] is a local cancellation/deadline handle and is
/// never serialized; the Infrastructure adapter owns the JSON envelope.
///
/// The contract lives in private parts of this library, grouped by
/// responsibility: query/scope, source, result, failure, consent, call context,
/// and the shared validation vocabulary. Only this file is imported, so the
/// public surface is exactly the types declared below.
///
/// Every type here validates its own input and throws [ArgumentError] when a
/// caller (typically the wire parser) hands it a value the frozen Phase 5
/// contract does not allow. Refusing is deliberate: a malformed grant, span, or
/// answer must never become application state. The error names the field and
/// the reason only: a question, title, quote, or answer is never echoed into an
/// exception, so note or answer text cannot leak through `toString`.
library;

import 'dart:convert';

part 'rag_call_context_part.dart';
part 'rag_consent_part.dart';
part 'rag_failure_part.dart';
part 'rag_query_part.dart';
part 'rag_result_part.dart';
part 'rag_source_part.dart';
part 'rag_validation_part.dart';

/// Wire version of the frozen Phase 5 RAG envelopes (`wireVersion`).
const int ragWireVersion = 1;
