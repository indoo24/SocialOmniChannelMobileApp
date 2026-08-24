/// Navigation.
///
/// Mobile-native structure over the same product concepts as the web client.
/// The desktop's three columns — Chats | Conversation | Customer — become a
/// push stack, because a phone cannot show three panes and pretending it can
/// is how a desktop UI ends up squeezed onto a handset.
///
///     Inbox  →  Conversation  →  Customer details
///
/// The web sidebar becomes a drawer. Its sections are the top-level routes
/// below, and both the drawer and these routes read `appSections` so a link is
/// never offered for a screen the role cannot open — and a *typed* or deep-
/// linked URL for one refuses explicitly instead of rendering a page whose
/// every request 403s.
///
/// Paths mirror the web routes so a deep link means the same thing in both
/// clients, which is what makes a push notification's target unambiguous.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/security/screen_security.dart';
import '../core/widgets/section_scaffold.dart';
import '../features/analytics/analytics_screen.dart';
import '../features/authentication/auth_controller.dart';
import '../features/authentication/login_screen.dart';
import '../features/conversations/inbox_screen.dart';
import '../features/customers/customer_details_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/directory/customer_profile_screen.dart';
import '../features/directory/customers_screen.dart';
import '../features/directory/employees_screen.dart';
import '../features/directory/teams_screen.dart';
import '../features/messages/conversation_screen.dart';
import '../features/settings/settings_screen.dart';
import 'navigation.dart';

class Routes {
  const Routes._();
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const inbox = '/inbox';
  static const customers = '/customers';
  static const employees = '/employees';
  static const teams = '/teams';
  static const analytics = '/analytics';
  static const settings = '/settings';

  static String conversation(int id) => '/inbox/$id';
  static String customer(int conversationId) =>
      '/inbox/$conversationId/customer';
  static String customerProfile(int customerId) => '/customers/$customerId';
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  /// Marks a route whose contents must not reach a screenshot or the
  /// app-switcher snapshot.
  ///
  /// Applied at the router rather than inside each screen for two reasons: it
  /// is one list to audit instead of a flag scattered across widgets, and the
  /// protection then covers every way a route is entered — tab, deep link,
  /// notification tap, restored location — rather than only the paths that
  /// remembered to opt in. See core/security/screen_security.dart.
  Widget sensitive(Widget child) => SecureScreen(child: child);

  /// Wraps a section so an unreachable one refuses rather than renders.
  ///
  /// The drawer already filters these out, so this is the deep-link case: a
  /// notification or a shared link pointing at a screen this role has no
  /// business in.
  Widget guard(String path, String label, Widget child) {
    return Consumer(
      builder: (context, ref, _) {
        final allowed = ref.watch(canAccessPathProvider(path));
        return allowed ? child : NoAccessScreen(sectionLabel: label);
      },
    );
  }

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
        return _safeNext(state.uri.queryParameters['next']) ?? Routes.inbox;
      }

      return null;
    },
    routes: [
      // The password field itself, and the pre-filled employee email above it.
      GoRoute(
        path: Routes.login,
        builder: (context, state) => sensitive(const LoginScreen()),
      ),
      GoRoute(
        path: Routes.dashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: Routes.inbox,
        builder: (context, state) => const InboxScreen(),
        routes: [
          // Message bodies — the most sensitive content the app renders.
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const _InvalidRoute();
              return sensitive(ConversationScreen(conversationId: id));
            },
            routes: [
              // Customer PII: name, phone, email, order history.
              GoRoute(
                path: 'customer',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  if (id == null) return const _InvalidRoute();
                  return sensitive(CustomerDetailsScreen(conversationId: id));
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.customers,
        builder: (context, state) =>
            guard(Routes.customers, 'Customers', const CustomersScreen()),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const _InvalidRoute();
              return guard(
                Routes.customers,
                'Customers',
                sensitive(CustomerProfileScreen(customerId: id)),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: Routes.employees,
        builder: (context, state) =>
            guard(Routes.employees, 'Employees', const EmployeesScreen()),
      ),
      GoRoute(
        path: Routes.teams,
        builder: (context, state) =>
            guard(Routes.teams, 'Teams', const TeamsScreen()),
      ),
      GoRoute(
        path: Routes.analytics,
        builder: (context, state) =>
            guard(Routes.analytics, 'Analytics', const AnalyticsScreen()),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      // The profile screen folded into Settings' Profile tab. Kept as a
      // redirect so a link stored on a device from an older build still lands
      // somewhere sensible.
      GoRoute(path: '/profile', redirect: (context, state) => Routes.settings),
    ],
    errorBuilder: (context, state) => const _InvalidRoute(),
  );
});

/// Validates the `next` parameter before it is used as a redirect target.
///
/// `next` is written by the app itself when an unauthenticated request for a
/// protected route is bounced to login — but it survives as a query parameter
/// on a URL, and a URL is the one part of navigation state that can arrive
/// from outside: a notification tap, a restored route, a link. Handing an
/// arbitrary decoded string back to `go_router` as a location is the shape of
/// an open redirect, so this narrows it to what it is actually for.
///
/// Accepted: a single-slash absolute in-app path (`/inbox/42`).
///
/// Rejected, each because it is a way to leave the app's own route space:
/// * anything with a scheme (`https://…`, `scenario://…`)
/// * protocol-relative paths (`//evil.example`), which many URL parsers read
///   as a host rather than a path
/// * anything not starting with `/`, which `go_router` would resolve
///   relatively against the current location
///
/// Returns null when the value is absent or unusable; the caller falls back to
/// the inbox.
String? _safeNext(String? raw) {
  if (raw == null || raw.isEmpty) return null;

  final String decoded;
  try {
    decoded = Uri.decodeComponent(raw);
  } on FormatException {
    // Malformed percent-encoding — not something this app ever produced.
    return null;
  }

  if (!decoded.startsWith('/')) return null;
  if (decoded.startsWith('//')) return null;
  if (decoded.contains('://')) return null;

  return decoded;
}

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
