/// Dependency wiring.
///
/// Riverpod was chosen over Bloc and plain Provider for three reasons that
/// matter to this app specifically:
///
/// * almost all of its state is *async server state* — REST reads invalidated
///   by WebSocket events — which `AsyncNotifier` models directly instead of
///   being hand-rolled around a Cubit;
/// * providers are overridable in tests without a widget tree or a DI
///   container, so networking and state are testable without pumping widgets;
/// * `ref.invalidate` gives the same "event says something changed, refetch
///   from the authority" pattern the web client already uses with TanStack
///   Query, keeping both clients conceptually identical.
///
/// One framework, no mixing.
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'api/api_client.dart';
import 'auth/auth_repository.dart';
import 'config/environment.dart';
import '../features/authentication/auth_controller.dart';
import 'notifications/device_repository.dart';
import 'realtime/realtime_client.dart';
import 'session/session_epoch.dart';
import 'storage/secure_store.dart';
import '../features/conversations/conversation_repository.dart';
import '../features/directory/directory_repository.dart';
import '../features/notifications/notification_repository.dart';

/// Overridden in `main()` once the cookie directory is known, and in tests
/// with an in-memory jar.
final cookieJarProvider = Provider<CookieJar>(
  (ref) => throw UnimplementedError('cookieJarProvider must be overridden'),
);

final environmentProvider = Provider<Environment>((ref) => Environment.current);

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient.create(
    cookieJar: ref.watch(cookieJarProvider),
    environment: ref.watch(environmentProvider),
    sessionEpoch: ref.watch(sessionEpochProvider),
    // Any 401 from the *current* session, from any call site, ends that
    // session once: socket down, cookie jar cleared, loaded data dropped. The
    // epoch the failing request was sent under travels with it, so a late
    // answer to an older session's request is recognised and ignored.
    //
    // Two deliberate choices here:
    //
    // * `ref.read` inside the callback rather than at build time — reading the
    //   auth controller eagerly would make this provider depend on one that
    //   depends back on it.
    // * `Future.microtask` — the 401 is raised while a repository call is in
    //   flight, which is frequently inside a provider's own `build`. Tearing
    //   the session down invalidates providers, and mutating the container
    //   from inside a build that is still running is not something Riverpod
    //   promises to handle. The async gap lets the failing build finish and
    //   throw its `SessionExpiredException` first, then does the teardown.
    onSessionExpired: (epoch) {
      Future.microtask(
        () => ref.read(authControllerProvider.notifier).onSessionExpired(epoch),
      );
    },
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),
    store: ref.watch(secureStoreProvider),
  );
});

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository(ref.watch(apiClientProvider));
});

final directoryRepositoryProvider = Provider<DirectoryRepository>((ref) {
  return DirectoryRepository(ref.watch(apiClientProvider));
});

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(ref.watch(apiClientProvider));
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(apiClientProvider));
});

final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient(
    cookieJar: ref.watch(cookieJarProvider),
    environment: ref.watch(environmentProvider),
    sessionEpoch: ref.watch(sessionEpochProvider),
    // A close code 4401/4403 means this socket's session is already dead —
    // the same condition a REST call reports as 401 or 403
    // `not_authenticated`. Route it through the same teardown rather than
    // letting the socket retry a rejected cookie on the ordinary backoff
    // schedule. See the comment on apiClientProvider's onSessionExpired for
    // why this is `ref.read` inside the callback and wrapped in a microtask.
    onUnauthorized: (epoch) {
      Future.microtask(
        () => ref.read(authControllerProvider.notifier).onSessionExpired(epoch),
      );
    },
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Builds the persistent cookie jar. Called once from `main()`.
///
/// Cookies are the session credential, so they live in the app's private
/// documents directory rather than a cache the OS may clear mid-shift.
Future<CookieJar> buildCookieJar() async {
  final directory = await getApplicationDocumentsDirectory();
  return PersistCookieJar(storage: FileStorage('${directory.path}/.cookies/'));
}
