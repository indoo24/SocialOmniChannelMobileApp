/// "Call": opens the phone's dialer with the customer's number filled in, for
/// the agent to review and press Call themselves.
///
/// Sits beside [SaveToContactsButton] and takes the same number — the one the
/// backend has for this customer — so the two always agree. Like it, the
/// button is offered even without a usable number, so that tapping it can say
/// why nothing happens. See `core/utils/phone_dialer.dart` for what is and is
/// not dialed.
library;

import 'package:flutter/material.dart';

import '../../core/utils/phone_dialer.dart';
import '../../l10n/l10n_extensions.dart';

class CallCustomerButton extends StatefulWidget {
  const CallCustomerButton({
    required this.phone,
    this.compact = false,
    super.key,
  });

  /// The number the backend gave for this customer, or empty when it gave
  /// none.
  final String phone;

  /// Smaller, for a section header beside other compact actions.
  final bool compact;

  @override
  State<CallCustomerButton> createState() => _CallCustomerButtonState();
}

class _CallCustomerButtonState extends State<CallCustomerButton> {
  bool _opening = false;

  Future<void> _call() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    setState(() => _opening = true);
    final outcome = await dialNumber(widget.phone);
    if (!mounted) return;
    setState(() => _opening = false);

    final message = switch (outcome) {
      DialOutcome.opened => null,
      DialOutcome.noNumber => l10n.callNoPhone,
      DialOutcome.invalidNumber => l10n.callInvalidPhone,
      DialOutcome.unavailable => l10n.callUnavailable,
    };
    if (message != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('callCustomerButton'),
      tooltip: context.l10n.callAction,
      visualDensity: widget.compact ? VisualDensity.compact : null,
      iconSize: widget.compact ? 20 : null,
      // The call is the action people reach for first from here, so it takes
      // the brand colour; saving to contacts keeps the neutral one.
      color: Theme.of(context).colorScheme.primary,
      onPressed: _opening ? null : _call,
      icon: const Icon(Icons.call_outlined),
    );
  }
}
