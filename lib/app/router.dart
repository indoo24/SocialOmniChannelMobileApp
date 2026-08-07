/// Navigation.
///
/// Mobile-native structure over the same product concepts as the web client.
/// The desktop's three columns — Chats | Conversation | Customer — become a
/// push stack, because a phone cannot show three panes and pretending it can
/// is how a desktop UI ends up squeezed onto a handset.
///
///     Inbox  →  Conversation  →  Customer details
///
/// Paths mirror the web routes so a deep link means the same thing in both
/// clients, which is what makes a push notification's target unambiguous.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/authentication/auth_controller.dart';
import '../features/authentication/login_screen.dart';
import '../features/conversations/inbox_screen.dart';
import '../features/customers/customer_details_screen.dart';
import '../features/messages/conversation_screen.dart';
import '../features/profile/profile_screen.dart';

class Routes {
  const Routes._();
  static const login = '/login';
  static const inbox = '/inbox';
  static const profile = '/profile';

  static String conversation(int id) => '/inbox/$id';
  static String customer(int conversationId) => '/inbox/$conversationId/customer';
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: Routes.inbox,
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);

      // Hold the current route while the session is being restored, so an
      // already-signed-in agent never sees the login screen flash past.
      if (auth.isRestoring) return null;

      final atLogin = state.matchedLocation == Routes.login;

      if (!auth.isAuthenticated) {
        // Preserve the intended destination — a notification tap that arrives
        // on an expired session should still land on its conversation once the
        // agent signs back in.
        final target = Uri.encodeComponent(state.matchedLocation);
        return atLogin ? null : '${Routes.login}?next=$target';
      }

      if (atLogin) {
        final next = state.uri.queryParameters['next'];
        return (next != null && next.isNotEmpty)
            ? Uri.decodeComponent(next)
            : Routes.inbox;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.inbox,
        builder: (context, state) => const InboxScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const _InvalidRoute();
              return ConversationScreen(conversationId: id);
            },
            routes: [
              GoRoute(
                path: 'customer',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  if (id == null) return const _InvalidRoute();
                  return CustomerDetailsScreen(conversationId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
    errorBuilder: (context, state) => const _InvalidRoute(),
  );
});

/// Bridges Riverpod auth state to go_router's Listenable-based refresh.
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(this._ref) {
    _subscription = _ref.listen<AuthState>(
      authControllerProvider,
      (_, _) => notifyListeners(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

class _InvalidRoute extends StatelessWidget {
  const _InvalidRoute();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('That screen does not exist.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(Routes.inbox),
                child: const Text('Back to inbox'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
