/// Customer fields admin — the Settings tab that manages field
/// *definitions* (`GET/POST/PATCH /customer-fields/`,
/// `POST /customer-fields/reorder/`), not one customer's values.
///
/// `custom_fields_section.dart` is the other customer-fields screen in this
/// app; it fills in a value for an existing field on one customer's profile
/// and is deliberately left untouched here — the two are different concerns
/// reading and writing different endpoints.
///
/// Visible with `customer.view` (read-only); Add/Edit/reorder/enable-disable
/// additionally need `customer_field.manage`, same belt-and-suspenders
/// pattern as `teams_screen.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/customer_fields.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../directory/directory_providers.dart';
import 'customer_field_definition_form_sheet.dart';

class CustomerFieldsSettingsTab extends ConsumerWidget {
  const CustomerFieldsSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(canProvider(Perm.customerView));
    if (!canView) {
      return Center(
        child: EmptyState(
          title: context.l10n.customerFieldsPermissionDenied,
          icon: Icons.lock_outline,
        ),
      );
    }

    final canManage = ref.watch(canProvider(Perm.customerFieldManage));
    final fieldsAsync = ref.watch(customerFieldDefinitionsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(customerFieldDefinitionsProvider);
        await ref.read(customerFieldDefinitionsProvider.future);
      },
      child: fieldsAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(customerFieldDefinitionsProvider),
        ),
        data: (fields) =>
            _CustomerFieldsList(fields: fields, canManage: canManage),
      ),
    );
  }
}

class _CustomerFieldsList extends StatelessWidget {
  const _CustomerFieldsList({required this.fields, required this.canManage});

  final List<CustomerFieldDefinition> fields;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...fields]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Text(
          context.l10n.customerFieldsTabTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          context.l10n.customerFieldsTabDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.lg),
        if (canManage)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: const Key('add-customer-field'),
              onPressed: () => showAddCustomerFieldSheet(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.l10n.addFieldAction),
            ),
          ),
        const SizedBox(height: Space.lg),
        if (sorted.isEmpty)
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: EmptyState(
              icon: Icons.dashboard_customize_outlined,
              title: context.l10n.noCustomerFieldsTitle,
              message: context.l10n.noCustomerFieldsMessage,
            ),
          )
        else
          for (int i = 0; i < sorted.length; i++) ...[
            _CustomerFieldCard(
              field: sorted[i],
              canManage: canManage,
              canMoveUp: i > 0,
              canMoveDown: i < sorted.length - 1,
              allFieldIds: sorted.map((f) => f.id).toList(),
              index: i,
            ),
            const SizedBox(height: Space.md),
          ],
      ],
    );
  }
}

class _CustomerFieldCard extends ConsumerStatefulWidget {
  const _CustomerFieldCard({
    required this.field,
    required this.canManage,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.allFieldIds,
    required this.index,
  });

  final CustomerFieldDefinition field;
  final bool canManage;
  final bool canMoveUp;
  final bool canMoveDown;
  final List<int> allFieldIds;
  final int index;

  @override
  ConsumerState<_CustomerFieldCard> createState() => _CustomerFieldCardState();
}

class _CustomerFieldCardState extends ConsumerState<_CustomerFieldCard> {
  bool _busy = false;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(customerFieldDefinitionsProvider);
      if (successMessage != null) _showMessage(successMessage);
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(int delta) async {
    final order = [...widget.allFieldIds];
    final from = widget.index;
    final to = from + delta;
    if (to < 0 || to >= order.length) return;
    final id = order.removeAt(from);
    order.insert(to, id);

    await _run(
      () => ref
          .read(directoryRepositoryProvider)
          .reorderCustomerFieldDefinitions(order),
      successMessage: context.l10n.customerFieldReorderedSnackbar,
    );
  }

  Future<void> _toggleActive() async {
    final nextActive = !widget.field.isActive;
    await _run(
      () => ref
          .read(directoryRepositoryProvider)
          .updateCustomerFieldDefinition(widget.field.id, isActive: nextActive),
      successMessage: nextActive
          ? context.l10n.customerFieldEnabledSnackbar
          : context.l10n.customerFieldDisabledSnackbar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final field = widget.field;

    return Card(
      key: Key('customer-field-${field.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: field.isActive ? 1 : 0.6,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                field.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            if (!field.isActive) ...[
                              const SizedBox(width: Space.xs),
                              StatusBadge(
                                label: context.l10n.customerFieldDisabledBadge,
                                dense: true,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          context.l10n.customerFieldKeyLabel(field.key),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    label: fieldTypeLabel(context, field.fieldType),
                    tone: BadgeTone.info,
                    dense: true,
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: Space.md),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (widget.canManage) ...[
                const SizedBox(height: Space.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      key: Key('customer-field-${field.id}-move-up'),
                      tooltip: context.l10n.moveFieldUpAction,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: (_busy || !widget.canMoveUp)
                          ? null
                          : () => _move(-1),
                    ),
                    IconButton(
                      key: Key('customer-field-${field.id}-move-down'),
                      tooltip: context.l10n.moveFieldDownAction,
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      onPressed: (_busy || !widget.canMoveDown)
                          ? null
                          : () => _move(1),
                    ),
                    IconButton(
                      key: Key('customer-field-${field.id}-edit'),
                      tooltip: context.l10n.editAction,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: _busy
                          ? null
                          : () => showEditCustomerFieldSheet(
                              context,
                              field: field,
                            ),
                    ),
                    IconButton(
                      key: Key('customer-field-${field.id}-toggle'),
                      tooltip: field.isActive
                          ? context.l10n.disableFieldAction
                          : context.l10n.enableFieldAction,
                      icon: Icon(
                        field.isActive
                            ? Icons.toggle_on_outlined
                            : Icons.toggle_off_outlined,
                        size: 22,
                        color: field.isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      onPressed: _busy ? null : _toggleActive,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
