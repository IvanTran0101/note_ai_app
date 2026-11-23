import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/note_intelligence/rag_app_service.dart';
import '../../application/note_intelligence/rag_state.dart';

/// Presentation adapter that mirrors one [RagAppService] into a [Listenable].
///
/// [RagAppService] is deliberately not a [ChangeNotifier] and owns all business
/// state, so this controller keeps no business state of its own: it reads the
/// current [RagState] before subscribing (never missing an already-published
/// value) and then forwards each streamed snapshot.
///
/// [dispose] only cancels the subscription. It never disposes the shared
/// service or gateway, and it never cancels an active question: a settings tile
/// or any other secondary view must not be able to revoke or cancel work that
/// the owning screen started.
final class RagController extends ChangeNotifier {
  /// Subscribes to [service] after reading its current snapshot.
  RagController(this.service) : _state = service.state {
    _subscription = service.stateStream.listen(_handleState);
  }

  /// The shared application service this controller observes.
  final RagAppService service;

  StreamSubscription<RagState>? _subscription;
  RagState _state;
  bool _disposed = false;

  /// The latest immutable snapshot of the shared service.
  RagState get state => _state;

  void _handleState(RagState next) {
    if (_disposed || next == _state) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
