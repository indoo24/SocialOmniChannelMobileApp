/// Sharing a phone contact in a conversation, and showing shared contacts.
///
/// ## Contract (`POST /conversations/{id}/reply/`)
///
///     { "message_type": "CONTACT",
///       "contacts": [{ "name": {"formatted_name": …},
///                      "phones": [{"phone": …, "type": "CELL|HOME|WORK|MAIN|IPHONE|"}] }],
///       "text": "", "client_message_id": … }
///
/// The message comes back (and in history and realtime) with the same
/// `contacts`. A contact is a message on its own: no text, no files.
///
/// ## Picking
///
/// One number of one contact, chosen in the platform's own picker over the
/// `scenario/contact_picker` channel — Android's phone-number picker
/// (`ACTION_PICK`, `Phone.CONTENT_TYPE`), iOS's `CNContactPickerViewController`.
/// Both hand back only the row the user tapped: **no contacts permission is
/// requested on either platform**, the address book is never read or
/// uploaded, and nothing is stored on the device. Names and numbers are never
/// logged.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/message.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../directory/call_customer_button.dart';
import 'conversation_controller.dart';

/// One number of one contact, as the platform picker returned it.
class PickedContact {
  const PickedContact({
    required this.name,
    required this.phone,
    this.type = '',
    this.label = '',
  });

  final String name;
  final String phone;

  /// WhatsApp's phone type (`CELL`, `HOME`, …) or empty — what is sent.
  final String type;

  /// The device's own label for the number ("Mobile", "جوال") — shown in
  /// the preview only.
  final String label;

  ContactCard toCard() => ContactCard(
    name: {'formatted_name': name.trim().isEmpty ? phone : name.trim()},
    phones: [ContactPhone(phone: phone.trim(), type: type)],
  );
}

/// The platform contact picker. Overridden in tests.
class ContactPhonePicker {
  const ContactPhonePicker();

  static const _channel = MethodChannel('scenario/contact_picker');

  /// The number the user picked, or null if they backed out. Throws a
  /// [PlatformException] when no picker could be shown.
  Future<PickedContact?> pickPhone() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('pickPhone');
    if (raw == null) return null;
    String field(String key) => (raw[key] as String?) ?? '';
    return PickedContact(
      name: field('name'),
      phone: field('phone'),
      type: field('type'),
      label: field('label'),
    );
  }
}

final contactPhonePickerProvider = Provider<ContactPhonePicker>(
  (ref) => const ContactPhonePicker(),
);

/// Picks a contact, previews it, and sends it into [conversationId] — the
/// whole flow behind the composer's "Contact" option. [replyTo] quotes the
/// message the agent was replying to, as any other send does.
Future<void> shareContact(
  BuildContext context,
  WidgetRef ref, {
  required int conversationId,
  QuotedMessage? replyTo,
  VoidCallback? onSent,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<PickedContact?> pick() async {
    try {
      final picked = await ref.read(contactPhonePickerProvider).pickPhone();
      if (picked != null && picked.phone.trim().isEmpty) {
        say(l10n.contactNoPhone);
        return null;
      }
      return picked;
    } on PlatformException {
      say(l10n.contactPickerUnavailable);
      return null;
    } on MissingPluginException {
      say(l10n.contactPickerUnavailable);
      return null;
    }
  }

  var picked = await pick();
  while (picked != null) {
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<_PreviewChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ContactSharePreview(contact: picked!),
    );
    if (choice == _PreviewChoice.change) {
      // A new pick replaces the old one; backing out of it keeps nothing.
      picked = await pick();
      continue;
    }
    if (choice != _PreviewChoice.send) return;

    onSent?.call();
    try {
      await ref
          .read(conversationControllerProvider(conversationId).notifier)
          .send('', contacts: [picked.toCard()], replyTo: replyTo);
    } on ApiException catch (error) {
      // The failed bubble stays in the thread with its retry; say why.
      say(error.message);
    }
    return;
  }
}

enum _PreviewChoice { send, change }

/// What will be sent: initials, name, the chosen number and its label —
/// with Send, Change and Cancel.
class ContactSharePreview extends StatelessWidget {
  const ContactSharePreview({required this.contact, super.key});

  final PickedContact contact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final name = contact.name.trim().isEmpty ? contact.phone : contact.name;
    final label = contact.label.isNotEmpty
        ? contact.label
        : phoneTypeLabel(l10n, contact.type);
    return SafeArea(
      child: Padding(
        key: const ValueKey('contactSharePreview'),
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.contactShareTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Row(
                children: [
                  _ContactAvatar(name: name, size: 44),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          key: const ValueKey('contactPreviewName'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _PhoneText(
                          contact.phone,
                          key: const ValueKey('contactPreviewPhone'),
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (label.isNotEmpty)
                          Text(
                            label,
                            key: const ValueKey('contactPreviewLabel'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.mutedForeground,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            // One line when it fits; stacked, Send first, when it does not
            // (a narrow phone, large text, a longer translation).
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              overflowDirection: VerticalDirection.up,
              spacing: Space.sm,
              overflowSpacing: Space.xs,
              children: [
                TextButton(
                  key: const ValueKey('contactPreviewCancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                OutlinedButton(
                  key: const ValueKey('contactPreviewChange'),
                  onPressed: () =>
                      Navigator.of(context).pop(_PreviewChoice.change),
                  child: Text(l10n.contactChangeAction),
                ),
                FilledButton.icon(
                  key: const ValueKey('contactPreviewSend'),
                  onPressed: () =>
                      Navigator.of(context).pop(_PreviewChoice.send),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(l10n.contactSendAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A shared contact in the thread — sent or received, live or from history:
/// initials, name, and each number with Call and Copy.
class ContactMessageCard extends StatelessWidget {
  const ContactMessageCard({
    required this.contact,
    required this.foreground,
    super.key,
  });

  final ContactCard contact;

  /// The bubble's text colour, so the card reads on either bubble.
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final name = contact.displayName.isNotEmpty
        ? contact.displayName
        : l10n.contactMessageLabel;
    final muted = foreground.withValues(alpha: 0.7);
    return ConstrainedBox(
      key: const ValueKey('contactMessageCard'),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ContactAvatar(name: name, size: 40),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      key: const ValueKey('contactCardName'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      l10n.contactMessageLabel,
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final phone in contact.phones) ...[
            Divider(
              height: Space.lg,
              color: foreground.withValues(alpha: 0.15),
            ),
            Row(
              key: ValueKey('contactCardPhone_${phone.phone}'),
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PhoneText(
                        phone.phone,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                        ),
                      ),
                      if (phoneTypeLabel(l10n, phone.type).isNotEmpty)
                        Text(
                          phoneTypeLabel(l10n, phone.type),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                          ),
                        ),
                    ],
                  ),
                ),
                CallCustomerButton(phone: phone.phone, compact: true),
                IconButton(
                  key: ValueKey('contactCopy_${phone.phone}'),
                  tooltip: l10n.contactCopyNumberAction,
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  color: foreground,
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: phone.phone));
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(content: Text(l10n.contactNumberCopied)),
                      );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A phone number laid out left to right in any language, so `+20 100…`
/// never comes out as `…100 20+` inside Arabic text.
class _PhoneText extends StatelessWidget {
  const _PhoneText(this.phone, {this.style, super.key});

  final String phone;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    phone,
    textDirection: TextDirection.ltr,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}

class _ContactAvatar extends StatelessWidget {
  const _ContactAvatar({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final words = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    final initials = words.isEmpty
        ? ''
        : words.take(2).map((w) => w.characters.first).join().toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: initials.isEmpty || RegExp(r'^[+\d]').hasMatch(initials)
          ? Icon(Icons.person_rounded, color: scheme.onPrimaryContainer)
          : Text(
              initials,
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: size * 0.36,
              ),
            ),
    );
  }
}

/// A readable label for a WhatsApp phone type; the raw value for one this
/// app has no word for; empty for none.
String phoneTypeLabel(AppLocalizations l10n, String type) =>
    switch (type.toUpperCase()) {
      '' => '',
      'CELL' || 'MOBILE' => l10n.phoneTypeMobile,
      'IPHONE' => 'iPhone',
      'HOME' => l10n.phoneTypeHome,
      'WORK' => l10n.phoneTypeWork,
      'MAIN' => l10n.phoneTypeMain,
      _ => type,
    };
