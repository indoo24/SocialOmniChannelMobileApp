/// Async reads for the directory, reporting and settings screens.
///
/// `FutureProvider` rather than `AsyncNotifier` throughout: none of these hold
/// local state beyond the fetch itself, and pull-to-refresh is
/// `ref.invalidate` + `ref.read(...future)`. The inbox is the exception and
/// keeps its `AsyncNotifier`, because it paginates and merges realtime updates.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/conversation.dart';
import '../../core/models/directory.dart';
import '../../core/providers.dart';

final dashboardProvider = FutureProvider<DashboardSummary>((ref) {
  return ref.watch(directoryRepositoryProvider).dashboard();
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

final employeeSearchProvider =
    NotifierProvider<SearchQueryController, String>(SearchQueryController.new);

final customerSearchProvider =
    NotifierProvider<SearchQueryController, String>(SearchQueryController.new);

final employeeDirectoryProvider =
    FutureProvider<List<DirectoryEmployee>>((ref) async {
  final page = await ref
      .watch(directoryRepositoryProvider)
      .employees(search: ref.watch(employeeSearchProvider));
  return page.results;
});

final customerDirectoryProvider = FutureProvider<List<Customer>>((ref) async {
  final page = await ref
      .watch(directoryRepositoryProvider)
      .customers(search: ref.watch(customerSearchProvider));
  return page.results;
});

final customerConversationsProvider =
    FutureProvider.family<List<Conversation>, int>((ref, id) async {
  final page =
      await ref.watch(directoryRepositoryProvider).customerConversations(id);
  return page.results;
});
