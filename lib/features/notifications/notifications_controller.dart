/// Controllers and state for in-app admin notifications.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/notification.dart';
import '../../core/providers.dart';

/// Provider for unread notification count.
class NotificationsUnreadCountNotifier extends AsyncNotifier<int> {
  @override
  FutureOr<int> build() async {
    final repo = ref.watch(notificationRepositoryProvider);
    return repo.unreadCount();
  }

  void decrement() {
    final current = state.value;
    if (current != null && current > 0) {
      state = AsyncData(current - 1);
    }
  }

  void markAllZero() {
    state = const AsyncData(0);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

final notificationsUnreadCountProvider =
    AsyncNotifierProvider<NotificationsUnreadCountNotifier, int>(
      NotificationsUnreadCountNotifier.new,
    );

class NotificationsState {
  const NotificationsState({
    required this.notifications,
    required this.page,
    required this.totalPages,
    required this.totalCount,
    required this.hasMore,
    this.isLoadingMore = false,
  });

  final List<NotificationModel> notifications;
  final int page;
  final int totalPages;
  final int totalCount;
  final bool hasMore;
  final bool isLoadingMore;

  NotificationsState copyWith({
    List<NotificationModel>? notifications,
    int? page,
    int? totalPages,
    int? totalCount,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return NotificationsState(
      notifications: notifications ?? this.notifications,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class NotificationsController extends AsyncNotifier<NotificationsState> {
  @override
  FutureOr<NotificationsState> build() async {
    final repo = ref.watch(notificationRepositoryProvider);
    final pageData = await repo.list(page: 1, pageSize: 20);

    return NotificationsState(
      notifications: pageData.results,
      page: pageData.page,
      totalPages: pageData.totalPages,
      totalCount: pageData.count,
      hasMore: pageData.hasMore,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(notificationRepositoryProvider);
      final pageData = await repo.list(page: 1, pageSize: 20);
      ref.invalidate(notificationsUnreadCountProvider);
      return NotificationsState(
        notifications: pageData.results,
        page: pageData.page,
        totalPages: pageData.totalPages,
        totalCount: pageData.count,
        hasMore: pageData.hasMore,
      );
    });
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final repo = ref.read(notificationRepositoryProvider);
      final nextPage = current.page + 1;
      final pageData = await repo.list(page: nextPage, pageSize: 20);

      final existingIds = current.notifications.map((n) => n.id).toSet();
      final newItems = pageData.results
          .where((n) => !existingIds.contains(n.id))
          .toList();

      state = AsyncData(
        current.copyWith(
          notifications: [...current.notifications, ...newItems],
          page: pageData.page,
          totalPages: pageData.totalPages,
          totalCount: pageData.count,
          hasMore: pageData.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  Future<void> markRead(int id) async {
    final current = state.value;
    if (current == null) return;

    final target = current.notifications.where((n) => n.id == id).firstOrNull;
    if (target == null || target.isRead) return;

    // Optimistic update
    final updatedList = current.notifications.map((n) {
      if (n.id == id) {
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();

    state = AsyncData(current.copyWith(notifications: updatedList));
    ref.read(notificationsUnreadCountProvider.notifier).decrement();

    try {
      final repo = ref.read(notificationRepositoryProvider);
      final updatedFromServer = await repo.markRead(id);

      // Reconcile with server response
      final reconciledList = (state.value ?? current).notifications.map((n) {
        if (n.id == id) {
          return updatedFromServer;
        }
        return n;
      }).toList();

      state = AsyncData(
        (state.value ?? current).copyWith(notifications: reconciledList),
      );
    } catch (_) {
      // Revert if request failed
      state = AsyncData(current);
      ref.invalidate(notificationsUnreadCountProvider);
    }
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;

    // Optimistic update
    final updatedList = current.notifications.map((n) {
      return n.copyWith(isRead: true);
    }).toList();

    state = AsyncData(current.copyWith(notifications: updatedList));
    ref.read(notificationsUnreadCountProvider.notifier).markAllZero();

    try {
      final repo = ref.read(notificationRepositoryProvider);
      await repo.markAllRead();
      ref.invalidate(notificationsUnreadCountProvider);
    } catch (_) {
      // Revert if request failed
      state = AsyncData(current);
      ref.invalidate(notificationsUnreadCountProvider);
    }
  }
}

final notificationsControllerProvider =
    AsyncNotifierProvider<NotificationsController, NotificationsState>(
      NotificationsController.new,
    );
