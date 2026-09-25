import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks the currently highlighted message ID so that tapping a quote/reply
/// preview temporarily highlights the original message and automatically
/// removes the highlight after a short duration.
class HighlightedMessageCoordinator extends Notifier<int?> {
  Timer? _timer;

  @override
  int? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// Highlights [messageId] for [duration].
  ///
  /// Any active highlight timer is canceled immediately, ensuring rapid
  /// taps smoothly cancel/replace the previous highlight.
  void highlight(
    int messageId, {
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    _timer?.cancel();
    state = messageId;
    _timer = Timer(duration, () {
      if (state == messageId) {
        state = null;
      }
    });
  }

  /// Clears any active highlight immediately.
  void clear() {
    _timer?.cancel();
    state = null;
  }
}

final highlightedMessageProvider =
    NotifierProvider<HighlightedMessageCoordinator, int?>(
      HighlightedMessageCoordinator.new,
    );
