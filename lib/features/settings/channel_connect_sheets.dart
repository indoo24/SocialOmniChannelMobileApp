/// Manual channel-connect forms — the non-OAuth alternative to the browser
/// hand-off `_connectAnother()` in `settings_screen.dart` uses for every
/// other connect flow.
///
/// Two backend endpoints, both `channel.manage`, both verified against Graph
/// **before** anything is stored — a bad token never produces a channel that
/// looks connected and fails on the first reply:
///
///  - `POST /integrations/whatsapp/connect/` (`DirectoryRepository.
///    connectWhatsApp`) — attach a number provisioned in the Meta dashboard
///    by `phone_number_id` + `access_token` (+ optional `waba_id`). Reused
///    here for two different intents that hit the identical endpoint:
///    "Add another number" (blank form) and "Update token" (the existing
///    channel's `phone_number_id` pre-filled and locked, only a fresh
///    `access_token` asked for). Swagger documents no separate update
///    endpoint, and its own 409 response text — "Already connected to
///    another workspace, or connected through a different onboarding
///    mode" — is about *another* workspace's claim, not a resubmission by
///    the rightful owner, so this does not invent update semantics beyond
///    what the contract already describes; if that reading is wrong for a
///    same-workspace resubmission, the resulting 409 surfaces to the admin
///    verbatim via the existing [ApiException] handling rather than being
///    swallowed or reinterpreted.
///  - `POST /integrations/instagram/connect/` (`DirectoryRepository.
///    connectInstagram`) — Instagram Login, a distinct product from the
///    Page-based OAuth flow: an Instagram user token pasted from Meta's
///    dashboard "Generate token" button. The account id is derived from the
///    token, not supplied by the caller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../conversations/inbox_controller.dart';
import '../directory/directory_providers.dart';

/// Opens the "Connect WhatsApp" selection sheet where the user chooses between:
/// 1. Coexistence mode ("I already use this number in WhatsApp Business" -> `coexistence`)
/// 2. Cloud API mode ("I want to set up a new number" -> `cloud_api`)
///
/// Returns the chosen mode string, or `null` if the sheet was dismissed without a choice.
Future<String?> showWhatsAppModeSelectionSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => const _WhatsAppModeSelectionSheet(),
  );
}

class _WhatsAppModeSelectionSheet extends StatelessWidget {
  const _WhatsAppModeSelectionSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(
        left: Space.lg,
        right: Space.lg,
        bottom: Space.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.connectWhatsAppAction,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            context.l10n.connectWhatsAppSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.lg),
          _buildOptionCard(
            context,
            title: context.l10n.whatsappOptionExistingTitle,
            description: context.l10n.whatsappOptionExistingDesc,
            buttonText: context.l10n.whatsappOptionExistingButton,
            isPrimary: true,
            onPressed: () => Navigator.of(context).pop('coexistence'),
          ),
          const SizedBox(height: Space.md),
          _buildOptionCard(
            context,
            title: context.l10n.whatsappOptionNewTitle,
            description: context.l10n.whatsappOptionNewDesc,
            buttonText: context.l10n.whatsappOptionNewButton,
            isPrimary: false,
            onPressed: () => Navigator.of(context).pop('cloud_api'),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required String title,
    required String description,
    required String buttonText,
    required bool isPrimary,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.25,
                  )
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.3 : 0.6,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: Space.md),
              SizedBox(
                width: double.infinity,
                child: isPrimary
                    ? FilledButton(
                        onPressed: onPressed,
                        child: Text(buttonText),
                      )
                    : OutlinedButton(
                        onPressed: onPressed,
                        child: Text(buttonText),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the "Add another number" / "Update token" sheet for WhatsApp.
///
/// [existing] `null` means a blank add-new-number form. Passing a channel
/// switches to update mode: `phone_number_id` is pre-filled and read-only
/// (the endpoint identifies the number by it — changing it would attach a
/// *different* number rather than rotate this one's credential), and only
/// `access_token` is asked for.
Future<void> showWhatsAppConnectSheet(
  BuildContext context, {
  ChannelConnection? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, controller) => _WhatsAppConnectSheet(
        existing: existing,
        scrollController: controller,
      ),
    ),
  );
}

class _WhatsAppConnectSheet extends ConsumerStatefulWidget {
  const _WhatsAppConnectSheet({this.existing, required this.scrollController});

  final ChannelConnection? existing;
  final ScrollController scrollController;

  bool get isUpdate => existing != null;

  @override
  ConsumerState<_WhatsAppConnectSheet> createState() =>
      _WhatsAppConnectSheetState();
}

class _WhatsAppConnectSheetState extends ConsumerState<_WhatsAppConnectSheet> {
  late final _phoneNumberId = TextEditingController(
    text: widget.existing?.externalAccountId,
  );
  final _accessToken = TextEditingController();
  final _wabaId = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phoneNumberId.dispose();
    _accessToken.dispose();
    _wabaId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final phoneNumberId = _phoneNumberId.text.trim();
    final accessToken = _accessToken.text.trim();

    if (phoneNumberId.isEmpty || accessToken.isEmpty) {
      setState(() => _error = context.l10n.fieldRequiredError);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final connected = await ref
          .read(directoryRepositoryProvider)
          .connectWhatsApp(
            phoneNumberId: phoneNumberId,
            accessToken: accessToken,
            wabaId: _wabaId.text.trim().isEmpty ? null : _wabaId.text.trim(),
          );

      if (!mounted) return;
      ref.invalidate(channelsProvider);
      // A newly attached (or re-credentialed) number can immediately start
      // carrying conversations the inbox has never fetched — same
      // reconciliation `_ChannelCardState._disconnect()` runs after a
      // disconnect, applied to the opposite direction of the same problem.
      ref.read(inboxControllerProvider.notifier).refreshQuietly();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isUpdate
                ? context.l10n.channelTokenUpdatedSnackbar
                : context.l10n.channelConnectedSnackbar(
                    connected.displayName.isEmpty
                        ? phoneNumberId
                        : connected.displayName,
                  ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Text(
          widget.isUpdate
              ? context.l10n.updateTokenSheetTitle
              : context.l10n.addAnotherNumberSheetTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          widget.isUpdate
              ? context.l10n.updateTokenSheetDescription
              : context.l10n.addAnotherNumberHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.lg),
        if (_error != null) ...[
          InlineError(message: _error!),
          const SizedBox(height: Space.md),
        ],
        TextField(
          controller: _phoneNumberId,
          enabled: !widget.isUpdate,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.l10n.phoneNumberIdFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _accessToken,
          obscureText: true,
          maxLines: 1,
          decoration: InputDecoration(
            labelText: context.l10n.accessTokenFieldLabel,
          ),
        ),
        if (!widget.isUpdate) ...[
          const SizedBox(height: Space.md),
          TextField(
            controller: _wabaId,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.wabaIdFieldLabel,
              helperText: context.l10n.wabaIdFieldOptionalHint,
            ),
          ),
        ],
        const SizedBox(height: Space.xl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.isUpdate
                        ? context.l10n.updateAction
                        : context.l10n.connectAction,
                  ),
          ),
        ),
      ],
    );
  }
}

/// Opens the "Use Instagram token" sheet.
Future<void> showInstagramTokenConnectSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
      maxChildSize: 0.8,
      minChildSize: 0.35,
      builder: (context, controller) =>
          _InstagramTokenConnectSheet(scrollController: controller),
    ),
  );
}

class _InstagramTokenConnectSheet extends ConsumerStatefulWidget {
  const _InstagramTokenConnectSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_InstagramTokenConnectSheet> createState() =>
      _InstagramTokenConnectSheetState();
}

class _InstagramTokenConnectSheetState
    extends ConsumerState<_InstagramTokenConnectSheet> {
  final _accessToken = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _accessToken.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final accessToken = _accessToken.text.trim();
    if (accessToken.isEmpty) {
      setState(() => _error = context.l10n.fieldRequiredError);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final connected = await ref
          .read(directoryRepositoryProvider)
          .connectInstagram(accessToken: accessToken);

      if (!mounted) return;
      ref.invalidate(channelsProvider);
      ref.read(inboxControllerProvider.notifier).refreshQuietly();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.channelConnectedSnackbar(
              connected.displayName.isEmpty
                  ? context.l10n.providerInstagram
                  : connected.displayName,
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Text(
          context.l10n.useInstagramTokenSheetTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          context.l10n.useInstagramTokenSheetDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.lg),
        if (_error != null) ...[
          InlineError(message: _error!),
          const SizedBox(height: Space.md),
        ],
        TextField(
          controller: _accessToken,
          obscureText: true,
          maxLines: 1,
          decoration: InputDecoration(
            labelText: context.l10n.instagramTokenFieldLabel,
          ),
        ),
        const SizedBox(height: Space.xl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(context.l10n.connectAction),
          ),
        ),
      ],
    );
  }
}
