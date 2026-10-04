import 'package:flutter/widgets.dart';

import '../../application/labels/label_application.dart';
import 'label_catalog_scope.dart';

/// Capture BEFORE opening a dialog so an old intent cannot write a new account.
final class LabelActionFence {
  LabelActionFence(this.app)
    : actor = app.currentActor(),
      epoch = app.generation();
  final LabelApplication app;
  final String actor;
  final int epoch;
  bool get live =>
      actor.isNotEmpty &&
      app.currentActor() == actor &&
      app.generation() == epoch;
  bool visible(BuildContext context) =>
      live && LabelCatalogScope.maybeOf(context)?.actor == actor;
  static LabelActionFence? capture(BuildContext context) {
    final scope = LabelCatalogScope.maybeOf(context), app = scope?.application;
    if (app == null || scope!.actor.isEmpty) return null;
    final fence = LabelActionFence(app);
    return fence.visible(context) ? fence : null;
  }
}
