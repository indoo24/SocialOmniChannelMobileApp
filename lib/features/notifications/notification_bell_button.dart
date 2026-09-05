/// Notification bell icon button with unread count badge.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/employee.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'notifications_controller.dart';

class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(canProvider(Perm.notificationView));
    if (!canView) return const SizedBox.shrink();

    final unreadAsync = ref.watch(notificationsUnreadCountProvider);
    final unread = unreadAsync.value ?? 0;

    final tooltip = unread > 0
        ? context.l10n.notificationsUnreadLabel(unread.toString())
        : context.l10n.notificationsTitle;

    return Semantics(
      button: true,
      label: tooltip,
      child: IconButton(
        tooltip: tooltip,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_outlined, size: 24),
            if (unread > 0)
              PositionedDirectional(
                top: -3,
                end: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  decoration: BoxDecoration(
                    color: ScenarioColors.destructive,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        onPressed: () => context.push(Routes.notifications),
      ),
    );
  }
}
