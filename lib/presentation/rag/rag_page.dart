import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/note_intelligence/rag_app_service.dart';
import '../../application/note_intelligence/rag_state.dart';
import '../../domain/note_intelligence/rag_models.dart';
import '../common/note_flow_primitives.dart';
import '../notes/notes_theme_tokens.dart';
import 'rag_answer_cards.dart';
import 'rag_consent_settings_tile.dart';
import 'rag_controller.dart';
import 'rag_copy.dart';
import 'rag_scope_selector.dart';

/// One responsive, single-turn "ask my notes" screen for Web and all Native
/// targets.
///
/// The page renders [RagAppService] state and forwards intent; it owns no
/// business rule. In particular it never validates a source itself, never
/// resends a question, never writes a note, and never reaches a provider. A
/// citation is reported to [onOpenSource], which owns the fresh sync, local
/// recheck, exactly one [RagAppService.validateSource], and the synchronous
/// open/highlight; the page only shows the in-flight and refused states.
///
/// The page keeps only view state (the selected scope, the question text, the
/// focused source open) and mirrors the service through a [RagController].
/// Closing the page cancels the question this screen started, but never
/// disposes the shared service or gateway.
final class RagPage extends StatefulWidget {
  /// Creates the page over the shared service.
  const RagPage({
    super.key,
    required this.service,
    required this.initialScope,
    required this.onOpenSource,
  });

  /// The application service that owns consent, runs, and answers.
  final RagAppService service;

  /// The scope the page starts on: a note scope when entered from a note, an
  /// account scope when entered from the workspace.
  final RagScope initialScope;

  /// Reports one citation open to the navigation owner.
  ///
  /// The owner performs the bounded fresh sync, local recheck, exactly one
  /// `validateSource`, and the synchronous open/highlight, then returns whether
  /// the source actually opened. The page never treats `true` as proof of
  /// navigation and never pops a route the owner already popped.
  final Future<bool> Function(RagSource source) onOpenSource;

  /// Key of the multiline question field.
  static const Key questionFieldKey = ValueKey<String>('rag-question-field');

  /// Key of the Ask action.
  static const Key askButtonKey = ValueKey<String>('rag-ask');

  /// Key of the Cancel action.
  static const Key cancelButtonKey = ValueKey<String>('rag-cancel');

  /// Key of the scope selector.
  static const Key scopeSelectorKey = ValueKey<String>('rag-scope-selector');

  /// Key of the consent control embedded in the page.
  static const Key consentTileKey = ValueKey<String>('rag-consent-tile');

  /// Key of the typed failure notice.
  static const Key failureKey = ValueKey<String>('rag-failure');

  /// Key of the answered result card.
  static const Key answerKey = ValueKey<String>('rag-answer');

  /// Key of the `NOT_ENOUGH_CONTEXT` card.
  static const Key notEnoughContextKey = ValueKey<String>(
    'rag-not-enough-context',
  );

  @override
  State<RagPage> createState() => _RagPageState();
}

final class _RagPageState extends State<RagPage> {
  late final TextEditingController _questionController;
  late final FocusNode _questionFocus;
  late RagController _controller;
  late RagScope _scope;

  String? _openingSourceId;
  RagFailureCode? _sourceFailure;
  String? _sourceFailureRequestId;

  /// The service this page submitted its still-pending question to, or null.
  ///
  /// This is ephemeral view intent, not business state: it only lets [dispose]
  /// cancel a question this page actually started. An idle page, or one whose
  /// service was replaced, never cancels a call another owner started.
  RagAppService? _pendingService;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController();
    _questionFocus = FocusNode();
    _scope = widget.initialScope;
    _controller = RagController(widget.service);
    // A pair retained for another scope must not reappear when this route
    // mounts on a different initial scope: clear it through the single owner.
    final RagScope? retained = widget.service.state.scope;
    if (retained != null && retained != widget.initialScope) {
      widget.service.selectScope(widget.initialScope);
    }
  }

  @override
  void didUpdateWidget(RagPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      _controller.dispose();
      _controller = RagController(widget.service);
    }
    // A different initial scope for the same route is applied through the same
    // single owner as a chip change, so the pair it replaces is cleared once.
    if (oldWidget.initialScope != widget.initialScope &&
        _scope != widget.initialScope) {
      _scope = widget.initialScope;
      widget.service.selectScope(widget.initialScope);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    // Closing the screen cancels only the question this screen submitted. The
    // shared service and gateway stay alive, and an idle page never cancels a
    // call another owner started on the same service.
    _pendingService?.cancel();
    _pendingService = null;
    _questionController.dispose();
    _questionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RagCopy copy = RagCopy.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(copy.pageTitle, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? _) {
            final RagState state = _controller.state;
            // A displayed pair is rendered only for the scope that produced
            // it; a scope switch hides the old pair without relabelling it.
            final bool sameScope = state.scope == _scope;
            final RagResult? result = sameScope ? state.result : null;
            final String? resultQuestion = sameScope
                ? state.resultQuestion
                : null;
            final RagFailure? failure = state.failure;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: NoteFlowSpacing.lg,
                vertical: NoteFlowSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: NoteFlowLayout.editorMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      RagConsentSettingsTile(
                        key: RagPage.consentTileKey,
                        service: widget.service,
                      ),
                      const SizedBox(height: NoteFlowSpacing.lg),
                      _buildScopeSelector(copy),
                      const SizedBox(height: NoteFlowSpacing.lg),
                      _buildQuestionField(copy),
                      const SizedBox(height: NoteFlowSpacing.md),
                      _buildActions(copy, state),
                      if (failure != null) ...<Widget>[
                        const SizedBox(height: NoteFlowSpacing.lg),
                        _buildFailure(copy, failure),
                      ],
                      if (result != null && resultQuestion != null) ...<Widget>[
                        const SizedBox(height: NoteFlowSpacing.lg),
                        if (result.isAnswered)
                          RagAnswerCard(
                            key: RagPage.answerKey,
                            question: resultQuestion,
                            answer: result.answer!,
                            sources: result.sources,
                            openingSourceId: _openingSourceId,
                            sourceFailure:
                                _sourceFailureRequestId == result.requestId
                                ? _sourceFailure
                                : null,
                            onOpenSource: (RagSource source) =>
                                _openSource(source, result.requestId),
                          )
                        else
                          RagNotEnoughContextCard(
                            key: RagPage.notEnoughContextKey,
                            question: resultQuestion,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildScopeSelector(RagCopy copy) {
    final String? noteId = widget.initialScope.noteId;
    return RagScopeSelector(
      key: RagPage.scopeSelectorKey,
      options: <RagScope>[
        if (noteId != null) RagScope.note(noteId),
        const RagScope.account(),
      ],
      selected: _scope,
      copy: copy,
      onSelected: _selectScope,
    );
  }

  Widget _buildQuestionField(RagCopy copy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NoteFlowSectionLabel(
          label: copy.questionLabel,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: NoteFlowSpacing.sm),
        // Ctrl/Cmd+Enter asks without taking plain Enter away from the
        // multiline field, so a line break still works on every platform.
        CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _submit,
            const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                _submit,
          },
          child: TextField(
            key: RagPage.questionFieldKey,
            controller: _questionController,
            focusNode: _questionFocus,
            minLines: 2,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: copy.questionHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NoteFlowRadius.input),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(RagCopy copy, RagState state) {
    final bool running = state.queryRunning;
    return Wrap(
      spacing: NoteFlowSpacing.sm,
      runSpacing: NoteFlowSpacing.sm,
      children: <Widget>[
        FilledButton.icon(
          key: RagPage.askButtonKey,
          onPressed: state.canAsk ? _submit : null,
          icon: const Icon(Icons.search, size: 18),
          label: Text(running ? copy.asking : copy.ask),
        ),
        OutlinedButton.icon(
          key: RagPage.cancelButtonKey,
          onPressed: running ? () => widget.service.cancel() : null,
          icon: const Icon(Icons.close, size: 18),
          label: Text(copy.cancel),
        ),
      ],
    );
  }

  Widget _buildFailure(RagCopy copy, RagFailure failure) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Text(
        copy.failureMessage(failure),
        key: RagPage.failureKey,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: tokens.error),
      ),
    );
  }

  void _selectScope(RagScope scope) {
    if (_scope == scope) {
      return;
    }
    setState(() {
      _scope = scope;
      _openingSourceId = null;
      _sourceFailure = null;
      _sourceFailureRequestId = null;
    });
    // The application service is the single owner: a scope change cancels the
    // run and any source check, then clears the retained pair for the old scope
    // in one synchronous update, so returning to it cannot revive the answer.
    widget.service.selectScope(scope);
  }

  void _submit() {
    if (!_controller.state.canAsk) {
      return;
    }
    setState(() {
      _openingSourceId = null;
      _sourceFailure = null;
      _sourceFailureRequestId = null;
    });
    // The exact field text is passed through; the service owns validation.
    final RagAppService service = widget.service;
    _pendingService = service;
    unawaited(
      service
          .ask(question: _questionController.text, scope: _scope)
          .whenComplete(() {
            if (identical(_pendingService, service)) {
              _pendingService = null;
            }
          }),
    );
  }

  Future<void> _openSource(RagSource source, String requestId) async {
    if (_openingSourceId != null) {
      return;
    }
    setState(() {
      _openingSourceId = source.sourceId;
      _sourceFailure = null;
      _sourceFailureRequestId = null;
    });

    RagFailureCode? failure;
    try {
      final bool opened = await widget.onOpenSource(source);
      if (!opened) {
        failure = RagFailureCode.sourceUnavailable;
      }
    } on RagFailure catch (error) {
      failure = error.code;
    } catch (_) {
      failure = RagFailureCode.unexpected;
    }

    // A callback that resolves after this screen is gone must not touch it.
    if (!mounted) {
      return;
    }
    setState(() {
      _openingSourceId = null;
      _sourceFailure = failure;
      _sourceFailureRequestId = failure == null ? null : requestId;
    });
  }
}
