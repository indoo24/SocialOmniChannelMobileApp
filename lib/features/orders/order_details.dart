/// The richer half of an order card, shared by every surface that shows one:
/// pricing adjustments, fulfilment, delivery, the payment record and who
/// follows the order up.
///
/// Each line renders only when it has something to say, so an order recorded
/// before these fields existed looks exactly as it did.
///
/// Fulfilment and payment are deliberately not status. They never make an
/// order a sale — only confirmation does — and the labels say "reported" where
/// the value is a claim.
library;

import 'package:flutter/material.dart';

import '../../core/models/performance.dart';
import '../../core/theme/tokens.dart';
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

    final recipient = joined([order.recipientName, order.recipientPhone], ' · ');
    final place = joined([order.city, order.governorate], '، ');
    final payment = joined([
      if (order.paymentMethod.isNotEmpty)
        paymentMethodLabel(context, order.paymentMethod),
      if (order.paymentStatus.isNotEmpty)
        paymentStatusLabel(context, order.paymentStatus),
    ], ' · ');
    final followUp = joined([order.assignedToName, order.assignedTeamName], ' · ');
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
      if (showFulfilment && !order.isEnded && fulfilment != null && fulfilment != 'NEW')
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
        line(Icons.event_outlined, l10n.orderDeliveryDue(order.expectedDeliveryDate!)),
      if (order.deliveryNotes.isNotEmpty) line(Icons.notes_outlined, order.deliveryNotes),
      if (payment.isNotEmpty) line(Icons.account_balance_wallet_outlined, payment),
      if (followUp.isNotEmpty) line(Icons.person_outline, l10n.orderFollowUpValue(followUp)),
      if (order.isEnded && order.cancellationReason.isNotEmpty)
        line(Icons.info_outline, l10n.orderCancellationReason(order.cancellationReason)),
    ];

    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
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
              context.l10n.orderFulfilmentValue(fulfilmentLabel(context, current)),
              style: style,
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: style?.color),
          ],
        ),
      ),
    );
  }
}
