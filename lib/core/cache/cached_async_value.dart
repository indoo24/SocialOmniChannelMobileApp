/// Rendering helper for screens backed by a session cache.
///
/// `AsyncValue.when` treats loading as "there is nothing to show", which is
/// right on a cold start and wrong everywhere else. Riverpod already carries
/// the previous value through a rebuild — a refresh or a filter change reads
/// as `AsyncLoading(value: <previous>)` — and a cache hit resolves on the very
/// next microtask, so `when` renders one frame of skeleton over data that was
/// never actually gone.
///
/// [whenCached] renders that retained value instead, and falls back to the
/// usual loading/error states only when there is genuinely nothing to show:
///
///   cold start, nothing cached  → loading (skeleton)
///   cache hit                   → data, immediately, no skeleton frame
///   pull-to-refresh with data   → previous data stays on screen
///   error with no previous data → error
///   error over previous data    → previous data stays on screen
///
/// The last case is deliberate: a failed refresh should not throw away a good
/// answer the user is reading. The [QueryCache] behaves the same way — a
/// failed fetch never overwrites a cached value — so the two agree. Errors on
/// a cold start still surface normally through [ErrorStateView].
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

extension CachedAsyncValue<T> on AsyncValue<T> {
  /// Like `when`, but prefers a retained previous value over the loading and
  /// error states.
  Widget whenCached({
    required Widget Function(T data) data,
    required Widget Function() loading,
    required Widget Function(Object error, StackTrace stackTrace) onError,
  }) {
    // `hasValue` stays true through a rebuild whenever a previous value
    // exists, which is exactly the "keep showing what we have" case. Testing
    // it rather than `value != null` keeps a legitimately-null T working.
    if (hasValue) return data(value as T);

    if (isLoading) return loading();

    final err = error;
    if (err != null) return onError(err, stackTrace ?? StackTrace.empty);

    return loading();
  }
}
