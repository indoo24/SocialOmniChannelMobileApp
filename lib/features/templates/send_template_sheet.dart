/// Bottom sheet for sending an approved WhatsApp template outbound.
///
/// Mirrors the web client's "Send template" dialog: pick a recipient — either
/// a customer already in the system, or a phone number typed by hand — see the
/// template body, and send.
///
/// Calls `POST /api/integrations/whatsapp/{channelId}/templates/send/` through
/// the existing [TemplatesRepository.sendOutboundTemplate]. The sending number
/// is the channel in the URL, never a field in the body, so the account picked
/// on the Templates screen is the account that sends.
///
/// Recipient validation is deliberately thin here. The backend refuses a local
/// number beginning with `0` rather than guessing its country code, and checks
/// approval, language and parameter count against Meta at send time; this
/// sheet surfaces those errors rather than restating the rules client-side and
/// risking a different answer.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/models/template.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'templates_providers.dart';

/// Which of the two recipient modes the sheet is showing.
enum TemplateRecipientMode { existingCustomer, newPhone }

class SendTemplateSheet extends ConsumerStatefulWidget {
  const SendTemplateSheet({
    required this.template,
    required this.channelId,
    required this.accountLabel,
    super.key,
  });

  final WhatsAppTemplate template;

  /// The WhatsApp channel selected on the Templates screen — both the send
  /// URL's `{id}` and the account named in the subtitle.
  final int channelId;
  final String accountLabel;

  static Future<bool?> show(
    BuildContext context, {
    required WhatsAppTemplate template,
    required int channelId,
    required String accountLabel,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SendTemplateSheet(
        template: template,
        channelId: channelId,
        accountLabel: accountLabel,
      ),
    );
  }

  @override
  ConsumerState<SendTemplateSheet> createState() => _SendTemplateSheetState();
}

class _SendTemplateSheetState extends ConsumerState<SendTemplateSheet> {
  final _searchController = TextEditingController();
  final _phoneController = TextEditingController();

  TemplateRecipientMode _mode = TemplateRecipientMode.existingCustomer;
  Customer? _selectedCustomer;
  Timer? _debounce;
  String _searchTerm = '';
  bool _sending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Enables/disables "Send template" as the field fills and empties.
    _phoneController.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _phoneController.removeListener(_onPhoneChanged);
    _searchController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onPhoneChanged() => setState(() {});

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // A short pause so each keystroke is not its own request — same interval
    // the saved-reply picker uses.
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _searchTerm = value.trim());
    });
  }

  void _setMode(TemplateRecipientMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      // The two modes name mutually exclusive recipients, and the request body
      // may carry only one. Clearing the other side keeps "what will be sent"
      // the same as what is on screen.
      _errorMessage = null;
      if (mode == TemplateRecipientMode.existingCustomer) {
        _phoneController.clear();
      } else {
        _selectedCustomer = null;
      }
    });
  }

  /// True when the sheet has enough to attempt a send. Deliberately shallow
  /// for the phone case — anything beyond "not empty" is the backend's call.
  bool get _hasRecipient => switch (_mode) {
    TemplateRecipientMode.existingCustomer => _selectedCustomer != null,
    TemplateRecipientMode.newPhone => _phoneController.text.trim().isNotEmpty,
  };

  Future<void> _send() async {
    if (_sending || !_hasRecipient) return;

    setState(() {
      _sending = true;
      _errorMessage = null;
    });

    final isCustomer = _mode == TemplateRecipientMode.existingCustomer;
    try {
      final result = await ref
          .read(templatesRepositoryProvider)
          .sendOutboundTemplate(
            widget.channelId,
            customerId: isCustomer ? _selectedCustomer!.id : null,
            phone: isCustomer ? null : _phoneController.text.trim(),
            templateName: widget.template.name,
            language: widget.template.language,
          );

      if (!mounted) return;
      // `customer_name` is the server's own label for whoever received it —
      // for a typed number that is the customer it just created or matched,
      // which the client has no other way to name.
      final recipientName = (result['customer_name'] as String?)?.trim();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.sendTemplateSentSnackbar(
              recipientName != null && recipientName.isNotEmpty
                  ? recipientName
                  : (isCustomer
                        ? _selectedCustomer!.displayName
                        : _phoneController.text.trim()),
            ),
          ),
          backgroundColor: ScenarioColors.success,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, bottomInset),
      decoration: BoxDecoration(
        color: isDark ? ScenarioColors.darkCard : ScenarioColors.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.lg),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: Space.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ),
            ),

            Text(
              context.l10n.sendTemplateSheetTitle(widget.template.name),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              context.l10n.sendTemplateSheetSubtitle(widget.accountLabel),
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? ScenarioColors.darkMutedForeground
                    : ScenarioColors.mutedForeground,
              ),
            ),
            const SizedBox(height: Space.lg),

            if (_errorMessage != null) ...[
              Container(
                key: const Key('sendTemplateError'),
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: ScenarioColors.dangerSurface,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(
                    color: ScenarioColors.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: ScenarioColors.danger,
                      size: 20,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: ScenarioColors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
            ],

            Text(
              context.l10n.sendTemplateRecipientLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.sm),
            _RecipientModeSelector(
              mode: _mode,
              enabled: !_sending,
              onChanged: _setMode,
            ),
            const SizedBox(height: Space.md),

            if (_mode == TemplateRecipientMode.existingCustomer)
              _CustomerPicker(
                controller: _searchController,
                searchTerm: _searchTerm,
                selected: _selectedCustomer,
                enabled: !_sending,
                onSearchChanged: _onSearchChanged,
                onSelected: (customer) => setState(() {
                  _selectedCustomer = customer;
                  _errorMessage = null;
                }),
              )
            else
              _PhoneField(controller: _phoneController, enabled: !_sending),

            const SizedBox(height: Space.lg),
            _TemplatePreview(body: widget.template.body),
            const SizedBox(height: Space.lg),

            // Wrap rather than Row: at 320px with a long localized label the
            // two buttons do not fit side by side, and a Row would overflow
            // rather than fold.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                TextButton(
                  onPressed: _sending
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton.icon(
                  key: const Key('sendTemplateSubmit'),
                  onPressed: (_sending || !_hasRecipient) ? null : _send,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: ScenarioColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.lg,
                      vertical: Space.md,
                    ),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: Text(context.l10n.sendTemplate),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );
  }
}

/// The two-up segmented control: Existing customer | New phone number.
class _RecipientModeSelector extends StatelessWidget {
  const _RecipientModeSelector({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final TemplateRecipientMode mode;
  final bool enabled;
  final ValueChanged<TemplateRecipientMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeButton(
            key: const Key('recipientModeCustomer'),
            icon: Icons.person_outline_rounded,
            label: context.l10n.sendTemplateExistingCustomer,
            selected: mode == TemplateRecipientMode.existingCustomer,
            enabled: enabled,
            onTap: () => onChanged(TemplateRecipientMode.existingCustomer),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: _ModeButton(
            key: const Key('recipientModePhone'),
            icon: Icons.phone_outlined,
            label: context.l10n.sendTemplateNewPhone,
            selected: mode == TemplateRecipientMode.newPhone,
            enabled: enabled,
            onTap: () => onChanged(TemplateRecipientMode.newPhone),
          ),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final foreground = selected
        ? ScenarioColors.primary
        : (isDark
              ? ScenarioColors.darkMutedForeground
              : ScenarioColors.mutedForeground);

    return Material(
      color: selected
          ? ScenarioColors.primary.withValues(alpha: isDark ? 0.22 : 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected
                  ? ScenarioColors.primary
                  : (isDark
                        ? ScenarioColors.darkBorder
                        : ScenarioColors.border),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: Space.xs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search field plus results, reusing [templateRecipientSearchProvider] —
/// which is the app's one customer-search endpoint behind a sheet-scoped key.
class _CustomerPicker extends ConsumerWidget {
  const _CustomerPicker({
    required this.controller,
    required this.searchTerm,
    required this.selected,
    required this.enabled,
    required this.onSearchChanged,
    required this.onSelected,
  });

  final TextEditingController controller;
  final String searchTerm;
  final Customer? selected;
  final bool enabled;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Customer> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final async = ref.watch(templateRecipientSearchProvider(searchTerm));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('templateCustomerSearch'),
          controller: controller,
          enabled: enabled,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.l10n.sendTemplateCustomerSearchHint,
            prefixIcon: const Icon(Icons.search, size: 20),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: Space.sm),
        Container(
          // Bounded so the list scrolls inside the sheet rather than pushing
          // the preview and Send button off the bottom.
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: isDark ? ScenarioColors.darkBorder : ScenarioColors.border,
            ),
          ),
          child: async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Space.lg),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(Space.md),
              child: ErrorStateView(
                error: error,
                onRetry: () =>
                    ref.invalidate(templateRecipientSearchProvider(searchTerm)),
              ),
            ),
            data: (customers) {
              if (customers.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Text(
                    context.l10n.sendTemplateNoCustomersFound,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? ScenarioColors.darkMutedForeground
                          : ScenarioColors.mutedForeground,
                    ),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: customers.length,
                itemBuilder: (context, index) {
                  final customer = customers[index];
                  return _CustomerRow(
                    customer: customer,
                    selected: selected?.id == customer.id,
                    enabled: enabled,
                    onTap: () => onSelected(customer),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Customer customer;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  /// `.characters.first` rather than `name[0]`: a display name can start with
  /// an emoji, and raw UTF-16 indexing would split it mid surrogate pair —
  /// `TextPainter` then throws "not well-formed UTF-16" trying to render it.
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasPhone = customer.phone.trim().isNotEmpty;

    return Material(
      color: selected
          ? ScenarioColors.primary.withValues(alpha: isDark ? 0.20 : 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          child: Row(
            children: [
              InitialsAvatar(
                initials: _initials(customer.displayName),
                imageUrl: customer.avatarUrl,
                size: 32,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    Text(
                      hasPhone
                          ? customer.phone
                          : context.l10n.sendTemplateNoPhoneOnFile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? ScenarioColors.darkMutedForeground
                            : ScenarioColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: ScenarioColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.sendTemplatePhoneLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.xs),
        TextField(
          key: const Key('templatePhoneInput'),
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.phone,
          // The number is dialled data, not prose: it reads left-to-right even
          // when the rest of the sheet is laid out right-to-left.
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            hintText: '+20 100 000 0001',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          context.l10n.sendTemplatePhoneHelper,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isDark
                ? ScenarioColors.darkMutedForeground
                : ScenarioColors.mutedForeground,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: isDark
            ? ScenarioColors.darkBackground
            : ScenarioColors.background,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isDark ? ScenarioColors.darkBorder : ScenarioColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.sendTemplatePreviewLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isDark
                  ? ScenarioColors.darkMutedForeground
                  : ScenarioColors.mutedForeground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
        ],
      ),
    );
  }
}
