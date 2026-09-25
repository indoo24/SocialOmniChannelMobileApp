/// Customer data — the details a human recorded about the customer.
///
/// "Customer data" here means what the web client means by it: free-form facts
/// somebody typed in ("Age: 23", "Adress: 10 st."), not the conversation's own
/// metadata. Status, priority, assignment, message counts and timestamps
/// describe the *thread* and stay in the conversation sheet where they were;
/// email/phone/location/language describe how to *reach* the customer and live
/// in Contact. This sheet is only the third thing: recorded facts.
///
/// Everything here is existing machinery — [CustomerFact],
/// `customerFactsProvider` (`GET /customers/{id}/facts/`) and
/// [showRecordCustomerDetailDialog] (`POST /customers/{id}/facts/`). The sheet
/// adds no endpoint of its own, and the dialog already invalidates the
/// provider on success, so a saved detail appears here without extra wiring.
///
/// Two kinds of fact are deliberately filtered out:
///
///  * `isTypedField` — a value for a custom field definition. It belongs under
///    that field in Contact, not loose in this list, or it would appear twice.
///  * `needsReview` — an analyzer guess nobody has accepted. Those live in the
///    review tray in the Orders card; showing an unconfirmed guess next to a
///    human-recorded fact is exactly the conflation `customer_record_sheet.dart`
///    warns about.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/performance.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../directory/directory_providers.dart';
import 'order_and_fact_dialogs.dart';

/// The recorded, human-facing facts out of a raw fact list.
///
/// Shared with the conversation sheet's preview so the card and the sheet can
/// never disagree about what counts as a customer detail.
List<CustomerFact> recordedCustomerFacts(List<CustomerFact> facts) {
  return facts.where((f) => !f.needsReview && !f.isTypedField).toList();
}

/// Opens the Customer data sheet for [customerId].
///
/// [canManage] gates the "+ Detail" affordance the same way the conversation
/// sheet gates its own record actions (`order.manage`), so the button is
/// absent rather than present-and-refused for an agent without it.
Future<void> showCustomerDataSheet(
  BuildContext context, {
  required int customerId,
  int? conversationId,
  bool canManage = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => _CustomerDataSheet(
        customerId: customerId,
        conversationId: conversationId,
        canManage: canManage,
        scrollController: controller,
      ),
    ),
  );
}

class _CustomerDataSheet extends ConsumerWidget {
  const _CustomerDataSheet({
    required this.customerId,
    required this.conversationId,
    required this.canManage,
    required this.scrollController,
  });

  final int customerId;
  final int? conversationId;
  final bool canManage;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final factsAsync = ref.watch(customerFactsProvider(customerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.sm, Space.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.customerDataTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canManage)
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(context.l10n.customerDataDetailButton),
                  onPressed: () => showRecordCustomerDetailDialog(
                    context,
                    ref: ref,
                    customerId: customerId,
                    conversationId: conversationId,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: factsAsync.when(
            loading: () => const LoadingState(),
            error: (error, _) => ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(customerFactsProvider(customerId)),
            ),
            data: (facts) {
              final recorded = recordedCustomerFacts(facts);
              if (recorded.isEmpty) {
                return EmptyState(
                  title: context.l10n.customerDataEmpty,
                  icon: Icons.fact_check_outlined,
                );
              }
              return ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.md,
                  Space.lg,
                  Space.xxl,
                ),
                itemCount: recorded.length,
                itemBuilder: (context, i) => CustomerDataRow(fact: recorded[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One recorded detail: `Key: value` on the left, who recorded it on the right.
///
/// The source badge is whatever the API returned — `EMPLOYEE` is given the
/// localized "Employee" label and a success tone, anything else (ANALYZER, or
/// a source added server-side later) is shown as-is rather than guessed at.
class CustomerDataRow extends StatelessWidget {
  const CustomerDataRow({required this.fact, super.key});

  final CustomerFact fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
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
            if (fact.source.isNotEmpty) ...[
              const SizedBox(width: Space.sm),
              StatusBadge(
                label: fact.source == 'EMPLOYEE'
                    ? context.l10n.employeeSourceBadge
                    : humanizeEnum(fact.source),
                tone: fact.source == 'EMPLOYEE'
                    ? BadgeTone.success
                    : BadgeTone.neutral,
                dense: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
