import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/labels/label_application.dart';
import '../../application/labels/local_label_state.dart';

enum LabelCatalogStatus { loading, ready, error }

/// A catalog-only cache. Refreshing it does not reload/remount the editor.
final class LabelCatalogHost extends StatefulWidget {
  const LabelCatalogHost({
    super.key,
    required this.application,
    required this.securityChanges,
    required this.child,
  });
  final LabelApplication? application;
  final Stream<void> securityChanges;
  final Widget child;
  @override
  State<LabelCatalogHost> createState() => _LabelCatalogHostState();
}

final class _LabelCatalogHostState extends State<LabelCatalogHost> {
  StreamSubscription<void>? _catalog, _security;
  List<LocalLabelState> _labels = const [];
  String _actor = '';
  int _read = 0;
  LabelCatalogStatus _status = LabelCatalogStatus.loading;
  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _catalog = widget.application?.changes.listen((_) => unawaited(_reload()));
    _security = widget.securityChanges.listen((_) {
      _read++;
      if (mounted) {
        setState(() {
          _labels = const [];
          _actor = '';
          _status = LabelCatalogStatus.loading;
        });
      }
      unawaited(_reload());
    });
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final app = widget.application;
    if (app == null) return;
    final sequence = ++_read;
    final actor = app.currentActor();
    if (mounted) {
      setState(() {
        if (_actor != actor) _labels = const [];
        _actor = actor;
        _status = LabelCatalogStatus.loading;
      });
    }
    try {
      final labels = await app.list();
      if (!mounted || sequence != _read || app.currentActor() != actor) return;
      setState(() {
        _actor = actor;
        _labels = List.unmodifiable(labels);
        _status = LabelCatalogStatus.ready;
      });
    } on Object {
      if (mounted && sequence == _read) {
        setState(() {
          if (app.currentActor() != actor) {
            _actor = '';
            _labels = const [];
          }
          _status = LabelCatalogStatus.error;
        });
      }
    }
  }

  @override
  void didUpdateWidget(LabelCatalogHost old) {
    super.didUpdateWidget(old);
    if (old.application != widget.application ||
        old.securityChanges != widget.securityChanges) {
      _catalog?.cancel();
      _security?.cancel();
      _read++;
      _labels = const [];
      _actor = '';
      _subscribe();
    }
  }

  @override
  void dispose() {
    _read++;
    _catalog?.cancel();
    _security?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LabelCatalogScope(
    application: widget.application,
    actor: _actor,
    labels: _labels,
    status: _status,
    child: widget.child,
  );
}

final class LabelCatalogScope extends InheritedWidget {
  const LabelCatalogScope({
    super.key,
    required this.application,
    required this.actor,
    required this.labels,
    this.status = LabelCatalogStatus.ready,
    required super.child,
  });
  final LabelApplication? application;
  final String actor;
  final List<LocalLabelState> labels;
  final LabelCatalogStatus status;
  static LabelCatalogScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LabelCatalogScope>();
  @override
  bool updateShouldNotify(LabelCatalogScope old) =>
      old.labels != labels ||
      old.status != status ||
      old.actor != actor ||
      old.application != application;
}
