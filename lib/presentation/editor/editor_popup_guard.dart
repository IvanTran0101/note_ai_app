import 'package:flutter/material.dart';

import 'rich_editor_adapter.dart';

/// Close only this editor's route when its snapshot/access/lifetime expires.
/// This also removes private link/equation input after lock, revoke or logout.
Future<T?> guardedEditorDialog<T>(
  BuildContext context,
  RichEditorAdapter adapter,
  RichSelectionSnapshot snapshot,
  WidgetBuilder builder,
) => showDialog<T>(
  context: context,
  builder: (context) => _EditorPopupGuard(
    adapter: adapter,
    snapshot: snapshot,
    child: builder(context),
  ),
);

Future<T?> guardedEditorSheet<T>(
  BuildContext context,
  RichEditorAdapter adapter,
  RichSelectionSnapshot snapshot,
  WidgetBuilder builder, {
  Color? barrierColor,
  BoxConstraints? constraints,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  barrierColor: barrierColor,
  constraints: constraints,
  builder: (context) => _EditorPopupGuard(
    adapter: adapter,
    snapshot: snapshot,
    child: SafeArea(top: false, child: builder(context)),
  ),
);

final class _EditorPopupGuard extends StatefulWidget {
  const _EditorPopupGuard({
    required this.adapter,
    required this.snapshot,
    required this.child,
  });
  final RichEditorAdapter adapter;
  final RichSelectionSnapshot snapshot;
  final Widget child;
  @override
  State<_EditorPopupGuard> createState() => _EditorPopupGuardState();
}

final class _EditorPopupGuardState extends State<_EditorPopupGuard> {
  bool closing = false;
  @override
  void initState() {
    super.initState();
    widget.adapter.addListener(check);
    widget.adapter.active.addListener(check);
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
  }

  void check() {
    if (!mounted ||
        closing ||
        widget.adapter.active.value &&
            widget.adapter.accepts(widget.snapshot, popupOwnsFocus: true)) {
      return;
    }
    closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    widget.adapter.removeListener(check);
    widget.adapter.active.removeListener(check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
