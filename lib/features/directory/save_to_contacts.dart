/// "Save to contacts": opens the phone's own new-contact screen with the
/// customer's name and number filled in, for the agent to review and save.
///
/// The app never writes to the address book itself — the system screen does,
/// and only when the agent taps its Save. That is also why no contacts
/// permission is needed on either platform. Only data the backend sent is
/// used: nothing is derived from the name, and a customer without a number is
/// told so rather than offered an empty card.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n_extensions.dart';

/// What happened after the new-contact screen was offered.
enum ContactSaveOutcome {
  /// The agent saved the contact.
  saved,

  /// The agent backed out without saving.
  cancelled,

  /// This device has no contacts screen the app can open.
  unavailable,
}

/// Opens the system new-contact screen. Behind a provider so tests can stand
/// in for the platform.
abstract interface class ContactSaver {
  Future<ContactSaveOutcome> createContact({
    required String name,
    required String phone,
  });
}

class NativeContactSaver implements ContactSaver {
  const NativeContactSaver();

  @override
  Future<ContactSaveOutcome> createContact({
    required String name,
    required String phone,
  }) async {
    try {
      final id = await FlutterContacts.native.showCreator(
        contact: Contact(
          // The whole name as the backend has it; the system editor splits
          // it into given/family names itself rather than the app guessing.
          name: name.isEmpty ? null : Name(first: name),
          phones: [Phone(number: phone)],
        ),
      );
      return id == null
          ? ContactSaveOutcome.cancelled
          : ContactSaveOutcome.saved;
    } on PlatformException {
      return ContactSaveOutcome.unavailable;
    } on MissingPluginException {
      return ContactSaveOutcome.unavailable;
    } on UnsupportedError {
      return ContactSaveOutcome.unavailable;
    }
  }
}

final contactSaverProvider = Provider<ContactSaver>(
  (ref) => const NativeContactSaver(),
);

/// The action, for the customer profile and the conversation's customer
/// details. [phone] is the number the backend gave for this customer, or
/// empty when it gave none.
class SaveToContactsButton extends ConsumerStatefulWidget {
  const SaveToContactsButton({
    required this.name,
    required this.phone,
    this.compact = false,
    super.key,
  });

  final String name;
  final String phone;

  /// Smaller, for a section header beside other compact actions.
  final bool compact;

  @override
  ConsumerState<SaveToContactsButton> createState() =>
      _SaveToContactsButtonState();
}

class _SaveToContactsButtonState extends ConsumerState<SaveToContactsButton> {
  bool _opening = false;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final phone = widget.phone.trim();
    if (phone.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.saveContactNoPhone)));
      return;
    }

    setState(() => _opening = true);
    final outcome = await ref
        .read(contactSaverProvider)
        .createContact(name: widget.name.trim(), phone: phone);
    if (!mounted) return;
    setState(() => _opening = false);

    final message = switch (outcome) {
      ContactSaveOutcome.saved => l10n.saveContactSaved,
      ContactSaveOutcome.unavailable => l10n.saveContactUnavailable,
      ContactSaveOutcome.cancelled => null,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('saveToContactsButton'),
      tooltip: context.l10n.saveContactAction,
      visualDensity: widget.compact ? VisualDensity.compact : null,
      iconSize: widget.compact ? 20 : null,
      onPressed: _opening ? null : _save,
      icon: _opening
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.person_add_alt_1_outlined),
    );
  }
}
