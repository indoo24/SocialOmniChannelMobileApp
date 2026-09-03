/// Async reads for the directory, reporting and settings screens.
///
/// `FutureProvider` rather than `AsyncNotifier` throughout: none of these hold
/// local state beyond the fetch itself, and pull-to-refresh is
/// `ref.invalidate` + `ref.read(...future)`. The inbox is the exception and
/// keeps its `AsyncNotifier`, because it paginates and merges realtime updates.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/conversation.dart';
import '../../core/models/customer_detail.dart';
import '../../core/models/directory.dart';
import '../../core/models/performance.dart';
import '../../core/models/routing_policy.dart';
import '../../core/providers.dart';
import '../authentication/auth_controller.dart';

final dashboardProvider = FutureProvider<DashboardSummary>((ref) {
  return ref.watch(directoryRepositoryProvider).dashboard();
});

final routingPolicyProvider = FutureProvider<RoutingPolicy>((ref) {
  return ref.watch(directoryRepositoryProvider).routingPolicy();
});

final channelVolumeProvider = FutureProvider<List<ChannelVolume>>((ref) {
  return ref.watch(directoryRepositoryProvider).channelVolume();
});

final teamsProvider = FutureProvider<List<Team>>((ref) async {
  final page = await ref.watch(directoryRepositoryProvider).teams();
  return page.results;
});

final channelsProvider = FutureProvider<List<ChannelConnection>>((ref) async {
  final page = await ref.watch(directoryRepositoryProvider).channels();
  return page.results;
});

final categoriesProvider = FutureProvider<List<ConversationCategory>>((ref) {
  return ref.watch(directoryRepositoryProvider).categories();
});

/// Channels the signed-in employee has collapsed out of view this session.
///
/// There is no backend field for "hidden" — [ChannelConnection.isMuted] is a
/// different, server-known concept (stop routing/surfacing conversations) and
/// [ChannelConnection.isActive] is the channel's connection state, whose
/// write path (`PATCH /channels/{id}/`) the API docs tie to archival
/// ("an archived channel is a 404 on every route"), not a lightweight
/// per-viewer collapse. So this is purely local, in-memory UI state — reset
/// on app restart — mirroring what a "Hide" affordance means in the web
/// screenshot: fold the card out of the way, nothing more.
class HiddenChannelsController extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void toggle(int channelId) {
    final next = Set<int>.from(state);
    if (!next.remove(channelId)) next.add(channelId);
    state = next;
  }
}

final hiddenChannelsProvider =
    NotifierProvider<HiddenChannelsController, Set<int>>(
      HiddenChannelsController.new,
    );

/// Search text for a directory screen.
///
/// One controller class, two providers: the two directories are searched
/// independently, so opening Customers must not inherit whatever was typed
/// into Employees.
class SearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void update(String value) => state = value;
  void clear() => state = '';
}

final employeeSearchProvider = NotifierProvider<SearchQueryController, String>(
  SearchQueryController.new,
);

final customerSearchProvider = NotifierProvider<SearchQueryController, String>(
  SearchQueryController.new,
);

final employeeDirectoryProvider = FutureProvider<List<DirectoryEmployee>>((
  ref,
) async {
  final page = await ref
      .watch(directoryRepositoryProvider)
      .employees(search: ref.watch(employeeSearchProvider));
  return page.results;
});

/// Currently-available agents — the whole set, not a client-side filter over
/// whichever page of [employeeDirectoryProvider] happens to be loaded.
final onlineEmployeesProvider = FutureProvider<List<DirectoryEmployee>>((ref) {
  return ref.watch(directoryRepositoryProvider).onlineEmployees();
});

final customerDirectoryProvider = FutureProvider<List<Customer>>((ref) async {
  final page = await ref
      .watch(directoryRepositoryProvider)
      .customers(search: ref.watch(customerSearchProvider));
  return page.results;
});

final customerDetailProvider = FutureProvider.family<CustomerDetail, int>((
  ref,
  customerId,
) {
  return ref.watch(directoryRepositoryProvider).customerDetail(customerId);
});

final customerConversationsProvider =
    FutureProvider.family<List<Conversation>, int>((ref, id) async {
      final page = await ref
          .watch(directoryRepositoryProvider)
          .customerConversations(id);
      return page.results;
    });

// --------------------------------------------------------------------------- //
// Performance
// --------------------------------------------------------------------------- //
/// Reporting window in days. Kept in a provider so the Analytics screen's
/// 7/14/30 switch refetches without threading state through the widget tree.
class PerformanceWindowController extends Notifier<int> {
  @override
  int build() => 14;

  void update(int days) => state = days;
}

final performanceWindowProvider =
    NotifierProvider<PerformanceWindowController, int>(
      PerformanceWindowController.new,
    );

final performanceProvider = FutureProvider<PerformanceReport>((ref) {
  return ref
      .watch(directoryRepositoryProvider)
      .performance(days: ref.watch(performanceWindowProvider));
});

/// The signed-in employee's own row, or null before it arrives.
///
/// Every employee is entitled to their own numbers, so this needs no
/// permission check — the endpoint returns exactly one row for an agent.
final myPerformanceProvider = Provider<EmployeePerformance?>((ref) {
  final me = ref.watch(currentEmployeeProvider);
  final report = ref.watch(performanceProvider).value;
  if (me == null || report == null) return null;

  for (final row in report.results) {
    if (row.employeeId == me.id) return row;
  }
  return null;
});

// --------------------------------------------------------------------------- //
// Orders and captured details
// --------------------------------------------------------------------------- //
final conversationOrdersProvider = FutureProvider.family<List<Order>, int>((
  ref,
  conversationId,
) {
  return ref
      .watch(directoryRepositoryProvider)
      .conversationOrders(conversationId);
});

final customerFactsProvider = FutureProvider.family<List<CustomerFact>, int>((
  ref,
  customerId,
) {
  return ref.watch(directoryRepositoryProvider).customerFacts(customerId);
});
