/// Orders and captured customer details, from inside a conversation.
///
/// A bottom sheet rather than a side panel — the web client has a third column
/// to spare and a phone does not, and an agent reaches for this at a specific
/// moment ("they just gave me their address") rather than watching it all day.
///
/// Two trays, kept visually apart on purpose:
///
/// **Suggestions** — what the analyzer read out of the chat. Amber, explicitly
/// labelled, and never merged into the customer profile until someone accepts
/// them. The analyzer is parsing prose: "my brother's number is…" reads exactly
/// like "my number is…", and a wrong number that looks confirmed is worse than
/// no number.
///
/// **Recorded** — what a human put there. Trusted.
///
/// The same rule governs orders: only CONFIRMED, which needs an employee to
/// attest, is ever counted as a sale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/employee.dart';
import '../../core/models/performance.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../authentication/auth_controller.dart';
import '../directory/directory_providers.dart';

/// Opens the record sheet for a conversation.
Future<void> showCustomerRecordSheet(
  BuildContext context, {
  required int conversationId,
  required int customerId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => _CustomerRecordSheet(
        conversationId: conversationId,
        customerId: customerId,
        scrollController: controller,
      ),
    ),
  );
}

class _CustomerRecordSheet extends ConsumerWidget {
  const _CustomerRecordSheet({
    required this.conversationId,
    required this.customerId,
    required this.scrollController,
  });

  final int conversationId;
  final int customerId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canManage = ref.watch(canProvider(Perm.orderManage));
    final orders = ref.watch(conversationOrdersProvider(conversationId));
    final facts = ref.watch(customerFactsProvider(customerId));

    final suggestedFacts = (facts.value ?? [])
        .where((f) => f.needsReview)
        .toList();
    final recordedFacts = (facts.value ?? [])
        .where((f) => !f.needsReview)
        .toList();
    final suggestedOrders = (orders.value ?? [])
        .where((o) => o.isSuggestion)
        .toList();
    final realOrders = (orders.value ?? [])
        .where((o) => !o.isSuggestion)
        .toList();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        if (suggestedFacts.isNotEmpty || suggestedOrders.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: ScenarioColors.warning),
              const SizedBox(width: Space.xs),
              Text(
                'Suggested from this chat',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Read out of the conversation automatically. Nothing here is saved '
            'to the customer until you accept it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.sm),
          for (final fact in suggestedFacts)
            _SuggestedDetail(
              fact: fact,
              customerId: customerId,
              canManage: canManage,
            ),
          for (final order in suggestedOrders)
            _OrderCard(
              order: order,
              conversationId: conversationId,
              customerId: customerId,
              canManage: canManage,
            ),
          const SizedBox(height: Space.lg),
        ],

        Row(
          children: [
            Expanded(
              child: Text(
                'Customer details',
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (canManage)
              TextButton.icon(
                onPressed: () => _showAddDetailDialog(
                  context,
                  ref,
                  customerId: customerId,
                  conversationId: conversationId,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
          ],
        ),
        if (facts.isLoading)
          const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: LoadingState(),
          )
        else if (recordedFacts.isEmpty)
          Text(
            'Nothing recorded yet. Anything the customer shares — an address, a '
            'phone number — can be saved here.',
            style: theme.textTheme.bodySmall,
          )
        else
          for (final fact in recordedFacts) _RecordedDetail(fact: fact),

        const SizedBox(height: Space.lg),
        Row(
          children: [
            Expanded(child: Text('Orders', style: theme.textTheme.titleSmall)),
            if (canManage)
              TextButton.icon(
                onPressed: () => _showRecordOrderDialog(
                  context,
                  ref,
                  customerId: customerId,
                  conversationId: conversationId,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Order'),
              ),
          ],
        ),
        if (orders.isLoading)
          const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: LoadingState(),
          )
        else if (realOrders.isEmpty)
          Text(
            'No orders recorded from this conversation.',
            style: theme.textTheme.bodySmall,
          )
        else
          for (final order in realOrders)
            _OrderCard(
              order: order,
              conversationId: conversationId,
              customerId: customerId,
              canManage: canManage,
            ),
      ],
    );
  }
}

// --------------------------------------------------------------------------- //
// Details
// --------------------------------------------------------------------------- //
class _RecordedDetail extends StatelessWidget {
  const _RecordedDetail({required this.fact});

  final CustomerFact fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: Space.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall,
                children: [
                  TextSpan(
                    text: '${humanizeEnum(fact.key)}: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: fact.value),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          StatusBadge(
            label: fact.source == 'EMPLOYEE' ? 'Employee' : 'Auto',
            tone: fact.source == 'EMPLOYEE'
                ? BadgeTone.success
                : BadgeTone.neutral,
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _SuggestedDetail extends ConsumerStatefulWidget {
  const _SuggestedDetail({
    required this.fact,
    required this.customerId,
    required this.canManage,
  });

  final CustomerFact fact;
  final int customerId;
  final bool canManage;

  @override
  ConsumerState<_SuggestedDetail> createState() => _SuggestedDetailState();
}

class _SuggestedDetailState extends ConsumerState<_SuggestedDetail> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.fact.value,
  );
  bool _editing = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _decide(bool confirmed) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(directoryRepositoryProvider)
          .reviewFact(
            customerId: widget.customerId,
            factId: widget.fact.id,
            confirmed: confirmed,
            // Only send a corrected value when it actually changed, so the
            // backend can tell "accepted as-is" from "accepted with a fix".
            value: confirmed && _controller.text != widget.fact.value
                ? _controller.text
                : null,
          );
      // Guarded together: ref.invalidate() on this State's own ref throws
      // "Using ref when a widget is about to or has been unmounted" if the
      // sheet closed while the request was in flight — the same check this
      // already needed for ScaffoldMessenger just covers both.
      if (mounted) {
        ref.invalidate(customerFactsProvider(widget.customerId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmed ? 'Saved to the customer' : 'Suggestion dismissed',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: Space.sm),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: ScenarioColors.warningSurface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: ScenarioColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  humanizeEnum(widget.fact.key),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                if (_editing)
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: const InputDecoration(isDense: true),
                    style: theme.textTheme.bodySmall,
                  )
                else
                  GestureDetector(
                    onTap: widget.canManage
                        ? () => setState(() => _editing = true)
                        : null,
                    child: Text(
                      _controller.text,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${(widget.fact.confidence * 100).round()}% confidence'
                  '${widget.canManage && !_editing ? ' · tap to correct' : ''}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (widget.canManage) ...[
            IconButton(
              tooltip: 'Save to the customer',
              onPressed: _busy ? null : () => _decide(true),
              icon: Icon(Icons.check, size: 20, color: ScenarioColors.success),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: "Dismiss — it won't be suggested again",
              onPressed: _busy ? null : () => _decide(false),
              icon: const Icon(Icons.close, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Orders
// --------------------------------------------------------------------------- //
class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({
    required this.order,
    required this.conversationId,
    required this.customerId,
    required this.canManage,
  });

  final Order order;
  final int conversationId;
  final int customerId;
  final bool canManage;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() => _busy = true);
    try {
      await action();
      // Guarded together — see the matching comment in
      // _SuggestedDetailState._decide(): ref.invalidate() throws if this
      // sheet closed while the request was in flight.
      if (mounted) {
        ref.invalidate(conversationOrdersProvider(widget.conversationId));
        ref.invalidate(performanceProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;

    final tone = switch (order.status) {
      'CONFIRMED' => BadgeTone.success,
      'SUGGESTED' => BadgeTone.warning,
      'CANCELLED' || 'REFUNDED' => BadgeTone.neutral,
      _ => BadgeTone.info,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: Space.sm),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: order.isSuggestion ? ScenarioColors.warningSurface : null,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: order.isSuggestion
              ? ScenarioColors.warning.withValues(alpha: 0.35)
              : theme.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 16),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  '${order.totalAmount} ${order.currency}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              StatusBadge(label: order.statusDisplay, tone: tone, dense: true),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.quantity}× ${item.productName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(item.lineTotal, style: theme.textTheme.bodySmall),
                ],
              ),
            ),

          if (order.evidence.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Container(
              padding: const EdgeInsets.only(left: Space.sm),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: ScenarioColors.warning, width: 2),
                ),
              ),
              child: Text(
                '“${order.evidence}”',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          const SizedBox(height: Space.xs),
          Text(
            order.isClaim
                ? 'Not counted as a sale until someone confirms it.'
                : order.isConfirmed
                ? 'Confirmed by ${order.confirmedByName.isEmpty ? 'an employee' : order.confirmedByName}'
                : '',
            style: theme.textTheme.labelSmall,
          ),

          if (widget.canManage && order.isClaim) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => ref
                                .read(directoryRepositoryProvider)
                                .confirmOrder(order.id),
                            'Order confirmed',
                          ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Confirm'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                IconButton(
                  tooltip: 'Cancel this order',
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => ref
                              .read(directoryRepositoryProvider)
                              .cancelOrder(order.id),
                          'Order cancelled',
                        ),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Entry dialogs
// --------------------------------------------------------------------------- //
Future<void> _showAddDetailDialog(
  BuildContext context,
  WidgetRef ref, {
  required int customerId,
  required int conversationId,
}) async {
  final keyController = TextEditingController();
  final valueController = TextEditingController();

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Record a customer detail'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: keyController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Detail',
              hintText: 'address',
            ),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: valueController,
            decoration: const InputDecoration(
              labelText: 'Value',
              hintText: '12 Nile St, Giza',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  // Neither controller is disposed here — see intelligence_panel.dart's
  // _LeadScoreSectionState._editScore() for why: showDialog's Future
  // resolves the instant Navigator.pop() runs in Save/Cancel's onPressed,
  // before the AlertDialog's own exit transition has finished animating
  // these still-mounted TextFields off screen. Disposing here races that
  // still-mounted subtree and can corrupt the element tree.
  if (saved != true) return;

  final key = keyController.text.trim();
  final value = valueController.text.trim();
  if (key.isEmpty || value.isEmpty) return;

  try {
    await ref
        .read(directoryRepositoryProvider)
        .recordFact(
          customerId: customerId,
          key: key,
          value: value,
          conversationId: conversationId,
        );
    // ref.invalidate() throws "Using ref when a widget is about to or has
    // been unmounted" if the sheet closed while recordFact() was in
    // flight — context.mounted is the same guard already needed below for
    // the error snackbar, just covering this call too.
    if (context.mounted) ref.invalidate(customerFactsProvider(customerId));
  } on ApiException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

Future<void> _showRecordOrderDialog(
  BuildContext context,
  WidgetRef ref, {
  required int customerId,
  required int conversationId,
}) async {
  final items = <Map<String, dynamic>>[];

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _OrderComposer(
      onChanged: (rows) {
        items
          ..clear()
          ..addAll(rows);
      },
    ),
  );

  if (confirmed != true || items.isEmpty) return;

  try {
    await ref
        .read(directoryRepositoryProvider)
        .recordOrder(
          customerId: customerId,
          conversationId: conversationId,
          items: items,
        );
    // Guarded together — see the matching comment in
    // _showAddDetailDialog(): ref.invalidate() throws if the sheet closed
    // while recordOrder() was in flight.
    if (context.mounted) {
      ref.invalidate(conversationOrdersProvider(conversationId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Order recorded. Confirm it once you've checked your own records.",
          ),
        ),
      );
    }
  } on ApiException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// Line-item entry.
///
/// Structured rows rather than a free-text box: the backend stores items
/// separately so "what sold this month" is a GROUP BY, and a text field here
/// would throw that away at the point of capture.
class _OrderComposer extends StatefulWidget {
  const _OrderComposer({required this.onChanged});

  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<_OrderComposer> createState() => _OrderComposerState();
}

class _OrderComposerState extends State<_OrderComposer> {
  final _rows = <_ItemRow>[_ItemRow()];

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  double get _total => _rows.fold(0, (sum, row) => sum + row.lineTotal);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Record an order'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What the customer asked for. Scenario has no payment data, so '
                'this is a record of the conversation, not a receipt.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: Space.md),
              for (var i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _rows[i].name,
                          decoration: const InputDecoration(
                            labelText: 'Product',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: TextField(
                          controller: _rows[i].quantity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _rows[i].price,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Price',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (_rows.length > 1)
                        IconButton(
                          onPressed: () => setState(() {
                            _rows.removeAt(i).dispose();
                          }),
                          icon: const Icon(Icons.close, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _rows.add(_ItemRow())),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add line'),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: theme.textTheme.titleSmall),
                  Text(
                    _total.toStringAsFixed(2),
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final payload = _rows
                .where((row) => row.name.text.trim().isNotEmpty)
                .map((row) => row.toJson())
                .toList();
            if (payload.isEmpty) return;
            widget.onChanged(payload);
            Navigator.of(context).pop(true);
          },
          child: const Text('Record order'),
        ),
      ],
    );
  }
}

class _ItemRow {
  final name = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController(text: '0.00');

  double get lineTotal =>
      (double.tryParse(price.text) ?? 0) * (int.tryParse(quantity.text) ?? 0);

  Map<String, dynamic> toJson() => {
    'product_name': name.text.trim(),
    'quantity': int.tryParse(quantity.text) ?? 1,
    'unit_price': price.text.trim().isEmpty ? '0.00' : price.text.trim(),
  };

  void dispose() {
    name.dispose();
    quantity.dispose();
    price.dispose();
  }
}
