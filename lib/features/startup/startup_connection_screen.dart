/// Shown at launch when a stored session could not be resumed because the
/// network or the server was unavailable ([RestoreIssue]). The session is
/// kept; this screen retries resuming it.
///
/// A retry first asks whether any network interface is up, and sends nothing
/// when none is. Otherwise it repeats the startup request itself
/// (`AuthController.restore`, `GET /auth/me/`) — the only proof the server
/// can be reached — and the app moves on only once that succeeds.
///
/// Besides the button, it retries on its own when the network comes back
/// and when the app returns to the foreground, after [autoRetryDelay] so a
/// burst of Wi-Fi / mobile-data changes makes one request, never one per
/// event. Nothing polls: with no event, nothing is sent.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/connectivity_monitor.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';

class StartupConnectionScreen extends ConsumerStatefulWidget {
  const StartupConnectionScreen({
    required this.issue,
    this.retrying = false,
    super.key,
  });

  /// Why the last attempt failed.
  final RestoreIssue issue;

  /// A retry is running (the auth controller is restoring).
  final bool retrying;

  /// How long the network has to stay up before an automatic retry.
  static const autoRetryDelay = Duration(seconds: 2);

  @override
  ConsumerState<StartupConnectionScreen> createState() =>
      _StartupConnectionScreenState();
}

class _StartupConnectionScreenState
    extends ConsumerState<StartupConnectionScreen>
    with WidgetsBindingObserver {
  StreamSubscription<bool>? _changes;
  Timer? _autoRetry;

  /// Whether a network interface is up, as last reported; null until known.
  bool? _networkUp;

  /// A retry is under way: checking the network, then restoring.
  bool _attempting = false;

  /// After a retry the person asked for failed again: why, to say so.
  RestoreIssue? _stillFailing;

  bool get _busy => _attempting || widget.retrying;

  /// No interface up overrides the last failure's reason: whatever it was,
  /// the first thing to fix now is turning Wi-Fi or data on.
  RestoreIssue get _shownIssue =>
      _networkUp == false ? RestoreIssue.offline : widget.issue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final monitor = ref.read(connectivityMonitorProvider);
    monitor.hasNetwork().then((up) {
      if (mounted && up != null) setState(() => _networkUp = up);
    });
    _changes = monitor.changes.listen(
      _onNetworkChanged,
      // A platform without the plugin: no events, the button still works.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes?.cancel();
    _autoRetry?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleAutoRetry();
  }

  void _onNetworkChanged(bool up) {
    if (!mounted) return;
    setState(() {
      _networkUp = up;
      if (up) _stillFailing = null;
    });
    if (up) {
      _scheduleAutoRetry();
    } else {
      // Gone again before the retry fired: wait for the next return.
      _autoRetry?.cancel();
    }
  }

  void _scheduleAutoRetry() {
    _autoRetry?.cancel();
    _autoRetry = Timer(
      StartupConnectionScreen.autoRetryDelay,
      () => _retry(asked: false),
    );
  }

  /// [asked] is true for the button: only then is a failure announced, as an
  /// automatic attempt is the screen quietly checking.
  Future<void> _retry({required bool asked}) async {
    if (_busy) return;
    _autoRetry?.cancel();
    setState(() {
      _attempting = true;
      _stillFailing = null;
    });
    try {
      final up = await ref.read(connectivityMonitorProvider).hasNetwork();
      if (!mounted) return;
      if (up == false) {
        // No interface: a request could only fail. Nothing is sent.
        setState(() {
          _networkUp = false;
          if (asked) _stillFailing = RestoreIssue.offline;
        });
        return;
      }
      if (up == true) setState(() => _networkUp = true);
      await ref.read(authControllerProvider.notifier).restore();
      // Success replaces this screen with the app; still here means not.
      if (!mounted) return;
      final issue = ref.read(authControllerProvider).restoreIssue;
      if (asked && issue != null) setState(() => _stillFailing = issue);
    } finally {
      if (mounted) setState(() => _attempting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final issue = _shownIssue;
    final (title, message) = _copy(l10n, issue);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.xl,
              vertical: Space.xl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - Space.xl * 2).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Illustration(issue: issue),
                      const SizedBox(height: Space.xl),
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          key: const Key('startupConnectionTitle'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.foreground,
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        message,
                        key: const Key('startupConnectionMessage'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.mutedForeground,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: Space.xl),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          key: const Key('startupRetryButton'),
                          onPressed: _busy ? null : () => _retry(asked: true),
                          icon: _busy
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                          label: Text(
                            _busy
                                ? l10n.startupRetryingButton
                                : l10n.startupRetryButton,
                          ),
                        ),
                      ),
                      if (_stillFailing case final failing?) ...[
                        const SizedBox(height: Space.md),
                        _StillFailingNote(text: _stillCopy(l10n, failing)),
                      ],
                      const SizedBox(height: Space.lg),
                      if (issue == RestoreIssue.offline)
                        _Hint(
                          icon: Icons.autorenew_rounded,
                          text: l10n.startupAutoRetryHint,
                        ),
                      _Hint(
                        icon: Icons.verified_user_outlined,
                        text: l10n.startupSessionKeptHint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static (String, String) _copy(AppLocalizations l10n, RestoreIssue issue) =>
      switch (issue) {
        RestoreIssue.offline => (
          l10n.startupOfflineTitle,
          l10n.startupOfflineMessage,
        ),
        RestoreIssue.unreachable => (
          l10n.startupUnreachableTitle,
          l10n.startupUnreachableMessage,
        ),
        RestoreIssue.serverError => (
          l10n.startupServerErrorTitle,
          l10n.startupServerErrorMessage,
        ),
      };

  static String _stillCopy(AppLocalizations l10n, RestoreIssue issue) =>
      switch (issue) {
        RestoreIssue.offline => l10n.startupStillOffline,
        RestoreIssue.unreachable => l10n.startupStillUnreachable,
        RestoreIssue.serverError => l10n.startupStillServerError,
      };
}

/// Concentric tinted rings around the icon for the problem, with a small
/// warning badge: calm, in the theme's own colours.
class _Illustration extends StatelessWidget {
  const _Illustration({required this.issue});

  final RestoreIssue issue;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final icon = switch (issue) {
      RestoreIssue.offline => Icons.wifi_off_rounded,
      RestoreIssue.unreachable => Icons.cloud_off_rounded,
      RestoreIssue.serverError => Icons.dns_outlined,
    };
    Widget ring(double size, double alpha) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primary.withValues(alpha: alpha),
      ),
    );

    return ExcludeSemantics(
      child: SizedBox(
        width: 168,
        height: 168,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ring(168, 0.05),
            ring(128, 0.09),
            Container(
              key: ValueKey('startupIllustration_${issue.name}'),
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surface,
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, size: 40, color: colors.primary),
            ),
            PositionedDirectional(
              end: 38,
              bottom: 38,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.warning,
                  border: Border.all(color: colors.surface, width: 3),
                ),
                child: const Icon(
                  Icons.priority_high_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A retry that was asked for and failed again — said where the button is,
/// and announced to screen readers.
class _StillFailingNote extends StatelessWidget {
  const _StillFailingNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('startupStillFailingNote'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm + 2,
        ),
        decoration: BoxDecoration(
          color: colors.warningSurface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: colors.warning),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.mutedForeground),
          const SizedBox(width: Space.sm),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}
