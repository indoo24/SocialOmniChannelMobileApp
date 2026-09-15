/// Shared order-rendering widgets, used everywhere an order or a recorded
/// customer detail is shown: the conversation record sheet
/// (`customer_record_sheet.dart`) and the customer profile screen
/// (`customer_profile_screen.dart`).
///
/// [OrderDetailsLines] is the richer half of an order card: pricing
/// adjustments, fulfilment, delivery, the payment record and who follows the
/// order up. Each line renders only when it has something to say, so an
/// order recorded before these fields existed looks exactly as it did.
///
/// Fulfilment and payment are deliberately not status. They never make an
/// order a sale — only confirmation does — and the labels say "reported" where
/// the value is a claim.
///
/// [OrderSummaryCard] is the read-only card shape (icon, amount, status
/// badge, line items, [OrderDetailsLines], confirmed-by/placed-at) that both
/// the record sheet's manage-capable `_OrderCard` and the profile screen's
/// plain Orders list build on, so the two surfaces never grow two different
/// ideas of what an order card looks like.
///
/// [RecordedFactTile] is the same extraction for one row of "known facts": a
/// key/value pair with a source badge (Employee vs. auto-extracted).
library;

import 'package:flutter/material.dart';

import '../../core/models/performance.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/badges.dart';
import '../../l10n/l10n_extensions.dart';

/// What an edit may set. CANCELLED is reached only by cancelling the order.
const settableFulfilmentStatuses = <String>[
  'NEW',
  'PROCESSING',
  'PACKING',
  'SHIPPED',
  'DELIVERED',
  'ON_HOLD',
];

String fulfilmentLabel(BuildContext context, String value) {
  final l10n = context.l10n;
  return switch (value) {
    'NEW' => l10n.fulfilmentNew,
    'PROCESSING' => l10n.fulfilmentProcessing,
    'PACKING' => l10n.fulfilmentPacking,
    'SHIPPED' => l10n.fulfilmentShipped,
    'DELIVERED' => l10n.fulfilmentDelivered,
    'ON_HOLD' => l10n.fulfilmentOnHold,
    'CANCELLED' => l10n.fulfilmentCancelled,
    _ => value,
  };
}

String paymentMethodLabel(BuildContext context, String value) {
  final l10n = context.l10n;
  return switch (value) {
    'CASH_ON_DELIVERY' => l10n.paymentMethodCashOnDelivery,
    'BANK_TRANSFER' => l10n.paymentMethodBankTransfer,
    'CARD' => l10n.paymentMethodCard,
    'WALLET' => l10n.paymentMethodWallet,
    'OTHER' => l10n.paymentMethodOther,
    _ => value,
  };
}

String paymentStatusLabel(BuildContext context, String value) {
  final l10n = context.l10n;
  return switch (value) {
    'UNPAID' => l10n.paymentStatusUnpaid,
    'PARTIALLY_PAID' => l10n.paymentStatusPartiallyPaid,
    'PAID' => l10n.paymentStatusPaid,
    'REFUNDED' => l10n.paymentStatusRefunded,
    _ => value,
  };
}

class OrderDetailsLines extends StatelessWidget {
  const OrderDetailsLines({
    super.key,
    required this.order,
    this.showFulfilment = true,
  });

  final Order order;

  /// Off where a [OrderFulfilmentPicker] already shows the value.
  final bool showFulfilment;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final small = Theme.of(context).textTheme.labelSmall;

    String joined(List<String> parts, String separator) =>
        parts.where((part) => part.isNotEmpty).join(separator);

    final recipient = joined([
      order.recipientName,
      order.recipientPhone,
    ], ' · ');
    final place = joined([order.city, order.governorate], '، ');
    final payment = joined([
      if (order.paymentMethod.isNotEmpty)
        paymentMethodLabel(context, order.paymentMethod),
      if (order.paymentStatus.isNotEmpty)
        paymentStatusLabel(context, order.paymentStatus),
    ], ' · ');
    final followUp = joined([
      order.assignedToName,
      order.assignedTeamName,
    ], ' · ');
    final fulfilment = order.fulfilmentStatus;

    Widget pair(String label, String value) => Row(
      children: [
        Expanded(child: Text(label, style: small)),
        Text(value, style: small),
      ],
    );

    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: small?.color),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: small)),
        ],
      ),
    );

    final lines = <Widget>[
      if (order.hasPricingAdjustments) ...[
        pair(l10n.orderSubtotalLabel, order.subtotal),
        if (Order.isNonZero(order.discount))
          pair(l10n.orderDiscountLabel, '−${order.discount}'),
        if (Order.isNonZero(order.shippingCost))
          pair(l10n.orderShippingLabel, '+${order.shippingCost}'),
      ],
      if (showFulfilment &&
          !order.isEnded &&
          fulfilment != null &&
          fulfilment != 'NEW')
        line(
          Icons.local_shipping_outlined,
          l10n.orderFulfilmentValue(fulfilmentLabel(context, fulfilment)),
        ),
      if (recipient.isNotEmpty || place.isNotEmpty)
        line(Icons.place_outlined, joined([recipient, place], ' — ')),
      if (order.address.isNotEmpty)
        line(
          Icons.home_outlined,
          order.landmark.isEmpty
              ? order.address
              : '${order.address} (${order.landmark})',
        ),
      if (order.expectedDeliveryDate != null)
        line(
          Icons.event_outlined,
          l10n.orderDeliveryDue(order.expectedDeliveryDate!),
        ),
      if (order.deliveryNotes.isNotEmpty)
        line(Icons.notes_outlined, order.deliveryNotes),
      if (payment.isNotEmpty)
        line(Icons.account_balance_wallet_outlined, payment),
      if (followUp.isNotEmpty)
        line(Icons.person_outline, l10n.orderFollowUpValue(followUp)),
      if (order.isEnded && order.cancellationReason.isNotEmpty)
        line(
          Icons.info_outline,
          l10n.orderCancellationReason(order.cancellationReason),
        ),
    ];

    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }
}

/// Moves an order's fulfilment. Offer it only where [Order.canMoveFulfilment].
class OrderFulfilmentPicker extends StatelessWidget {
  const OrderFulfilmentPicker({
    super.key,
    required this.order,
    required this.onChanged,
    this.busy = false,
  });

  final Order order;
  final ValueChanged<String> onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final current = order.fulfilmentStatus ?? 'NEW';
    final style = Theme.of(context).textTheme.labelMedium;

    return PopupMenuButton<String>(
      key: ValueKey('fulfilment-picker-${order.id}'),
      enabled: !busy,
      tooltip: context.l10n.orderFulfilmentLabel,
      initialValue: current,
      onSelected: (value) {
        if (value != current) onChanged(value);
      },
      itemBuilder: (menuContext) => [
        for (final value in settableFulfilmentStatuses)
          PopupMenuItem<String>(
            value: value,
            child: Text(fulfilmentLabel(menuContext, value)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_shipping_outlined, size: 16, color: style?.color),
            const SizedBox(width: 4),
            Text(
              context.l10n.orderFulfilmentValue(
                fulfilmentLabel(context, current),
              ),
              style: style,
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: style?.color),
          ],
        ),
      ),
    );
  }
}

/// Read-only order card: icon, amount and status, line items,
/// [OrderDetailsLines], confirmed-by/not-counted line, and optionally
/// [placedAt] and management [actions] a caller appends below.
///
/// The record sheet's own `_OrderCard` wraps this with confirm/cancel
/// buttons; the customer profile screen (which is read-only — orders are
/// managed from the conversation, not here) uses it as-is.
class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({
    required this.order,
    this.showPlacedAt = false,
    this.actions,
    super.key,
  });

  final Order order;

  /// Shows an "Ordered" timestamp line below the confirmed-by line — the
  /// customer profile's Orders section wants this; the conversation record
  /// sheet, already scoped to one thread's timeline, does not.
  final bool showPlacedAt;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tone = switch (order.status) {
      'CONFIRMED' => BadgeTone.success,
      'SUGGESTED' => BadgeTone.warning,
      'CANCELLED' || 'REFUNDED' => BadgeTone.neutral,
      _ => BadgeTone.info,
    };

    return Container(
      key: Key('order-card-${order.id}'),
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

          OrderDetailsLines(order: order),

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

          if (order.isClaim || order.isConfirmed) ...[
            const SizedBox(height: Space.xs),
            Text(
              order.isClaim
                  ? context.l10n.notCountedAsSaleMessage
                  : context.l10n.confirmedByMessage(
                      order.confirmedByName.isEmpty
                          ? context.l10n.confirmedByUnknownEmployee
                          : order.confirmedByName,
                    ),
              style: theme.textTheme.labelSmall,
            ),
          ],

          if (showPlacedAt && order.placedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              context.l10n.orderedAtLabel(
                formatDateTime(context, order.placedAt),
              ),
              style: theme.textTheme.labelSmall,
            ),
          ],

          if (actions != null) ...[const SizedBox(height: Space.sm), actions!],
        ],
      ),
    );
  }
}

/// One row of a customer's recorded (not suggested) facts: a key/value pair
/// with a source badge distinguishing what an employee typed from what the
/// analyzer inferred.
class RecordedFactTile extends StatelessWidget {
  const RecordedFactTile({required this.fact, super.key});

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
            label: fact.source == 'EMPLOYEE'
                ? context.l10n.employeeSourceBadge
                : context.l10n.autoSourceBadge,
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
