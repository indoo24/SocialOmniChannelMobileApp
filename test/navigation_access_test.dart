/// The drawer must offer a role exactly what that role can use.
///
/// Two clients now navigate the same product, so the failure this guards
/// against is drift: the web sidebar hiding Analytics from agents while the
/// phone shows it, or a section reachable by deep link that the drawer took
/// care to hide. The table in `app/navigation.dart` is the single answer, and
/// these assert it against the real permission sets the backend sends.
///
/// The backend enforces all of this regardless — see
/// `backend/tests/test_role_visibility.py`. This is about not showing people
/// doors they cannot open.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/app/navigation.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';

/// Permission sets exactly as `apps/core/permissions.py` grants them.
const _agent = {
  'conversation.reply',
  'conversation.note',
  'conversation.change_status',
  'conversation.change_category',
  'conversation.assign_self',
  'conversation.confirm_purchase',
  'conversation.refresh_intelligence',
  'employee.view',
  'team.view',
  'customer.view',
};

const _teamLeader = {
  ..._agent,
  'conversation.change_priority',
  'conversation.assign_any',
  'analytics.view',
};

const _supervisor = {
  ..._teamLeader,
  'conversation.delete_message',
  'customer.manage',
  'channel.view',
};

const _qa = {
  'conversation.note',
  'employee.view',
  'team.view',
  'customer.view',
  'analytics.view',
};

Employee _employee(Set<String> permissions, {String role = 'AGENT'}) => Employee(
      id: 1,
      email: 'someone@acme.test',
      fullName: 'Sam Person',
      initials: 'SP',
      role: role,
      roleDisplay: role,
      availability: 'ONLINE',
      permissions: permissions,
      visibilityScope: 'ASSIGNED',
      organization: const Organization(id: 1, name: 'Acme Retail'),
    );

ProviderContainer _containerFor(Employee? employee) {
  final container = ProviderContainer(
    overrides: [currentEmployeeProvider.overrideWithValue(employee)],
  );
  addTearDown(container.dispose);
  return container;
}

List<String> _labelsFor(Set<String> permissions) {
  final container = _containerFor(_employee(permissions));
  return container
      .read(accessibleSectionsProvider)
      .map((section) => section.label)
      .toList();
}

void main() {
  group('drawer sections', () {
    test('an agent gets everything except Analytics', () {
      expect(
        _labelsFor(_agent),
        ['Dashboard', 'Inbox', 'Customers', 'Employees', 'Teams', 'Settings'],
      );
    });

    test('a team leader gains Analytics', () {
      expect(_labelsFor(_teamLeader), contains('Analytics'));
    });

    test('a supervisor sees every section', () {
      expect(
        _labelsFor(_supervisor),
        [
          'Dashboard',
          'Inbox',
          'Customers',
          'Employees',
          'Teams',
          'Analytics',
          'Settings',
        ],
      );
    });

    test('QA reviews history, so it keeps Analytics and the directories', () {
      final labels = _labelsFor(_qa);
      expect(labels, contains('Analytics'));
      expect(labels, contains('Customers'));
      expect(labels, contains('Inbox'));
    });

    test('Dashboard, Inbox and Settings are offered to every role', () {
      for (final permissions in [_agent, _teamLeader, _supervisor, _qa]) {
        final labels = _labelsFor(permissions);
        expect(labels, containsAll(['Dashboard', 'Inbox', 'Settings']));
      }
    });

    test('a signed-out container offers nothing', () {
      final container = _containerFor(null);
      expect(container.read(accessibleSectionsProvider), isEmpty);
    });
  });

  group('route guard', () {
    test('refuses a section the role lacks, whatever route it came from', () {
      final container = _containerFor(_employee(_agent));
      expect(container.read(canAccessPathProvider('/analytics')), isFalse);
      expect(container.read(canAccessPathProvider('/customers')), isTrue);
    });

    test('allows paths outside the table, which are guarded server-side', () {
      // A conversation is reached through the inbox and filtered by the
      // backend's own visibility rule; the table has no opinion on it.
      final container = _containerFor(_employee(_agent));
      expect(container.read(canAccessPathProvider('/inbox/42')), isTrue);
    });

    test('every gated section agrees with its drawer entry', () {
      for (final permissions in [_agent, _teamLeader, _supervisor, _qa]) {
        final container = _containerFor(_employee(permissions));
        final offered = container
            .read(accessibleSectionsProvider)
            .map((s) => s.path)
            .toSet();

        for (final section in appSections) {
          expect(
            container.read(canAccessPathProvider(section.path)),
            offered.contains(section.path),
            reason: 'drawer and guard disagree about ${section.path}',
          );
        }
      }
    });

    test('the landing path is one the role can actually open', () {
      for (final permissions in [_agent, _teamLeader, _supervisor, _qa]) {
        final container = _containerFor(_employee(permissions));
        final landing = container.read(landingPathProvider);
        expect(container.read(canAccessPathProvider(landing)), isTrue);
      }
    });
  });
}
