/// Dialogs for recording customer facts and orders.
///
/// Matches the Web visual and behavioral specification:
/// - "Record a customer detail": Detail (key) and Value fields with validation.
/// - "Record an order": Multi-line product, quantity, unit price, dynamic total.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import '../directory/directory_providers.dart';

/// Opens the Web-matching "Record a customer detail" dialog.
Future<bool?> showRecordCustomerDetailDialog(
  BuildContext context, {
  WidgetRef? ref,
  required int customerId,
  int? conversationId,
}) {
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => _RecordDetailDialog(
      customerId: customerId,
      conversationId: conversationId,
    ),
  );
}

class _RecordDetailDialog extends ConsumerStatefulWidget {
  const _RecordDetailDialog({required this.customerId, this.conversationId});

  final int customerId;
  final int? conversationId;

  @override
  ConsumerState<_RecordDetailDialog> createState() =>
      _RecordDetailDialogState();
}

class _RecordDetailDialogState extends ConsumerState<_RecordDetailDialog> {
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final key = _keyController.text.trim();
    final value = _valueController.text.trim();

    if (key.isEmpty || value.isEmpty) {
      setState(() => _error = context.l10n.detailRequiredError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(directoryRepositoryProvider)
          .recordFact(
            customerId: widget.customerId,
            key: key,
            value: value,
            conversationId: widget.conversationId,
          );

      if (!mounted) return;
      ref.invalidate(customerFactsProvider(widget.customerId));
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.savedToCustomerMessage)),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Failed to save customer detail.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, 0),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.md,
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              context.l10n.recordDetailDialogTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.recordDetailDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.md),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm,
                    vertical: Space.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
              ],

              // Detail (Key) Field
              Text(
                context.l10n.detailFieldLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.xs),
              TextField(
                controller: _keyController,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.l10n.detailFieldHint,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
              ),
              const SizedBox(height: Space.md),

              // Value Field
              Text(
                context.l10n.valueFieldLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.xs),
              TextField(
                controller: _valueController,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.l10n.valueFieldHint,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: 10,
            ),
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
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

/// Opens the Web-matching "Record an order" dialog.
Future<bool?> showRecordOrderDialog(
  BuildContext context, {
  WidgetRef? ref,
  required int customerId,
  int? conversationId,
}) {
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => _RecordOrderDialog(
      customerId: customerId,
      conversationId: conversationId,
    ),
  );
}

class _RecordOrderDialog extends ConsumerStatefulWidget {
  const _RecordOrderDialog({required this.customerId, this.conversationId});

  final int customerId;
  final int? conversationId;

  @override
  ConsumerState<_RecordOrderDialog> createState() => _RecordOrderDialogState();
}

class _RecordOrderDialogState extends ConsumerState<_RecordOrderDialog> {
  final _rows = <_OrderLineRowData>[_OrderLineRowData()];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  double get _total => _rows.fold(0.0, (sum, row) => sum + row.lineTotal);

  void _addLine() {
    if (_busy) return;
    setState(() => _rows.add(_OrderLineRowData()));
  }

  void _removeLine(int index) {
    if (_busy || _rows.length <= 1) return;
    setState(() {
      final removed = _rows.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _submit() async {
    if (_busy) return;

    final validItems = <Map<String, dynamic>>[];
    for (final row in _rows) {
      final name = row.name.text.trim();
      if (name.isNotEmpty) {
        final qty = int.tryParse(row.quantity.text.trim()) ?? 1;
        final price = double.tryParse(row.price.text.trim());
        if (price == null || price < 0) {
          setState(() => _error = context.l10n.validPriceError);
          return;
        }
        validItems.add({
          'product_name': name,
          'quantity': qty > 0 ? qty : 1,
          'unit_price': price.toStringAsFixed(2),
        });
      }
    }

    if (validItems.isEmpty) {
      setState(() => _error = context.l10n.atLeastOneProductError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(directoryRepositoryProvider)
          .recordOrder(
            customerId: widget.customerId,
            conversationId: widget.conversationId,
            items: validItems,
          );

      if (!mounted) return;
      if (widget.conversationId != null) {
        ref.invalidate(conversationOrdersProvider(widget.conversationId!));
      }
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.orderRecordedMessage)),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Failed to record order.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, 0),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.md,
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              context.l10n.recordOrderDialogTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.orderComposerDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.md),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm,
                    vertical: Space.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
              ],

              // Order Lines
              for (var i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Product Name
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: _rows[i].name,
                          enabled: !_busy,
                          decoration: InputDecoration(
                            hintText: context.l10n.productFieldLabel,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: Space.sm,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: Space.xs),

                      // Quantity
                      SizedBox(
                        width: 58,
                        child: TextField(
                          controller: _rows[i].quantity,
                          enabled: !_busy,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: context.l10n.qtyFieldLabel,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: Space.xs),

                      // Unit Price
                      SizedBox(
                        width: 78,
                        child: TextField(
                          controller: _rows[i].price,
                          enabled: !_busy,
                          textAlign: TextAlign.end,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            hintText: context.l10n.priceFieldLabel,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),

                      if (_rows.length > 1) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: context.l10n.removeLineTooltip,
                          icon: const Icon(Icons.close, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: _busy ? null : () => _removeLine(i),
                        ),
                      ],
                    ],
                  ),
                ),

              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _busy ? null : _addLine,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(context.l10n.addLineButton),
                ),
              ),

              const Divider(height: Space.lg),

              // Total Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.l10n.totalLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _total.toStringAsFixed(2),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: 10,
            ),
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(context.l10n.recordOrderButton),
        ),
      ],
    );
  }
}

class _OrderLineRowData {
  final name = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController(text: '0.00');

  double get lineTotal {
    final qty = int.tryParse(quantity.text.trim()) ?? 0;
    final p = double.tryParse(price.text.trim()) ?? 0.0;
    return qty * p;
  }

  void dispose() {
    name.dispose();
    quantity.dispose();
    price.dispose();
  }
}
