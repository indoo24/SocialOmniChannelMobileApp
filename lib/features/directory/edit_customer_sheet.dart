/// Edit Customer — `PATCH /customers/{id}/`, gated on `customer.manage`.
///
/// A bottom sheet, the same shape as `notes_sheet.dart`/`conversion_sheet.dart`:
/// a `ConsumerStatefulWidget` that stays open and shows its own loading/error
/// state while the request is in flight, and only pops on success — see
/// `conversation_actions_sheet.dart`'s `_ActionsSheetState._run()` for the
/// exact close-on-success/stay-open-on-error convention this follows.
///
/// Only fields the admin actually touched are sent: [_EditCustomerSheetState]
/// diffs each controller against the value it was seeded with, matching the
/// spec's "only send fields that are actually being edited when practical."
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/customer_detail.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'directory_providers.dart';

/// Opens the Edit Customer sheet, prefilled from [customer].
Future<void> showEditCustomerSheet(
  BuildContext context, {
  required CustomerDetail customer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _EditCustomerSheet(customer: customer, scrollController: controller),
    ),
  );
}

class _EditCustomerSheet extends ConsumerStatefulWidget {
  const _EditCustomerSheet({
    required this.customer,
    required this.scrollController,
  });

  final CustomerDetail customer;
  final ScrollController scrollController;

  @override
  ConsumerState<_EditCustomerSheet> createState() => _EditCustomerSheetState();
}

class _EditCustomerSheetState extends ConsumerState<_EditCustomerSheet> {
  late final _displayName = TextEditingController(
    text: widget.customer.displayName,
  );
  late final _email = TextEditingController(text: widget.customer.email);
  late final _phone = TextEditingController(text: widget.customer.phone);
  late final _preferredLanguage = TextEditingController(
    text: widget.customer.preferredLanguage,
  );
  late final _country = TextEditingController(text: widget.customer.country);
  late final _city = TextEditingController(text: widget.customer.city);
  late final _lifecycleStage = TextEditingController(
    text: widget.customer.lifecycleStage,
  );
  late final _tags = TextEditingController(text: widget.customer.tags);
  late final _notes = TextEditingController(text: widget.customer.notes);

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _phone.dispose();
    _preferredLanguage.dispose();
    _country.dispose();
    _city.dispose();
    _lifecycleStage.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  Map<String, dynamic> _diff() {
    final customer = widget.customer;
    final fields = <String, dynamic>{};
    void put(String key, String current, String original) {
      if (current.trim() != original) fields[key] = current.trim();
    }

    put('display_name', _displayName.text, customer.displayName);
    put('email', _email.text, customer.email);
    put('phone', _phone.text, customer.phone);
    put(
      'preferred_language',
      _preferredLanguage.text,
      customer.preferredLanguage,
    );
    put('country', _country.text, customer.country);
    put('city', _city.text, customer.city);
    put('lifecycle_stage', _lifecycleStage.text, customer.lifecycleStage);
    put('tags', _tags.text, customer.tags);
    put('notes', _notes.text, customer.notes);
    return fields;
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final fields = _diff();
    if (fields.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(directoryRepositoryProvider)
          .updateCustomer(widget.customer.id, fields);
      // Guarded together — see conversation_actions_sheet.dart's
      // _ActionsSheetState._run(): ref/Navigator use here throws "Using ref
      // when a widget is about to or has been unmounted" if this sheet
      // closed some other way while updateCustomer() was in flight.
      if (!mounted) return;
      ref.invalidate(customerDetailProvider(widget.customer.id));
      ref.invalidate(customerDirectoryProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.customerUpdatedSnackbar)),
      );
    } on ApiException catch (error) {
      // Left open on failure — every controller above still holds what the
      // admin typed, per the spec's "do not lose unsaved form state on a
      // failed request."
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
          context.l10n.editCustomerTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.lg),
        if (_error != null) ...[
          InlineError(message: _error!),
          const SizedBox(height: Space.md),
        ],
        TextField(
          controller: _displayName,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: context.l10n.displayNameFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: context.l10n.emailFieldLabel),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: context.l10n.phoneFieldLabel),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _city,
                decoration: InputDecoration(
                  labelText: context.l10n.cityFieldLabel,
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: TextField(
                controller: _country,
                decoration: InputDecoration(
                  labelText: context.l10n.countryFieldLabel,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _preferredLanguage,
          decoration: InputDecoration(
            labelText: context.l10n.languageLabel,
            hintText: 'en',
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _lifecycleStage,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: context.l10n.lifecycleFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _tags,
          decoration: InputDecoration(labelText: context.l10n.tagsFieldLabel),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.customerNotesFieldLabel,
          ),
        ),
        const SizedBox(height: Space.xl),
        FilledButton(
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
              : Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}
