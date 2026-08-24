/// Employee performance, rendered for a phone.
///
/// A performance number is read as a judgement about a person, so every figure
/// carries enough context to be argued with. Three rules:
///
/// 1. **Never render an absent measurement as zero.** "No replies yet" and
///    "0 seconds" are opposite claims. Nulls become an em-dash with a reason.
/// 2. **Show the denominator.** An average response of 40s means nothing
///    without knowing it came from three replies or three hundred.
/// 3. **Label inference as inference.** Lead-score lift is movement while
///    someone held a conversation, not proof they caused it.
library;

import 'package:flutter/material.dart';

import '../../core/models/performance.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';

/// Seconds to a compact duration: `45s`, `4m 20s`, `2h 10m`.
///
/// Null renders as an em-dash, never `0s` — in a performance report those are
/// opposite claims, and collapsing them turns a missing measurement into a
/// flattering one.
String formatDuration(num? seconds) {
  if (seconds == null) return '—';
  if (seconds < 60) return '${seconds.round()}s';

  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    final rest = (seconds % 60).round();
    return rest > 0 ? '${minutes}m ${rest}s' : '${minutes}m';
  }

  final hours = minutes ~/ 60;
  final restMinutes = minutes % 60;
  return restMinutes > 0 ? '${hours}h ${restMinutes}m' : '${hours}h';
}

/// Seconds as timesheet hours — always h/m, never seconds.
String formatHours(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = ((seconds % 3600) / 60).round();
  if (hours == 0) return '${minutes}m';
  return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
}

class PerformanceCard extends StatelessWidget {
  const PerformanceCard({
    required this.row,
    this.showIdentity = true,
    super.key,
  });

  final EmployeePerformance row;
  final bool showIdentity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lift = row.leadScoreLift;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showIdentity) ...[
              Row(
                children: [
                  InitialsAvatar(
                    initials: row.initials,
                    imageUrl: row.avatarUrl,
                    size: 36,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Row(
                          children: [
                            PresenceDot(
                              availability: row.availability,
                              size: 7,
                            ),
                            const SizedBox(width: Space.xs),
                            Text(
                              row.role.replaceAll('_', ' ').toLowerCase(),
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
            ],

            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Avg response',
                    value: formatDuration(row.averageResponseSeconds),
                    hint: row.responsesCounted > 0
                        ? '${row.responsesCounted} '
                              '${row.responsesCounted == 1 ? 'reply' : 'replies'} · '
                              'median ${formatDuration(row.medianResponseSeconds)}'
                        : 'No replies yet',
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Lead score',
                    value: lift == null
                        ? '—'
                        : '${lift > 0 ? '+' : ''}${lift.toStringAsFixed(0)}',
                    hint: lift == null
                        ? 'No baseline recorded'
                        : '${row.leadScoreAtAssignment?.toStringAsFixed(0)} → '
                              '${row.leadScoreNow?.toStringAsFixed(0)}',
                    tone: lift == null
                        ? null
                        : lift > 0
                        ? ScenarioColors.success
                        : lift < 0
                        ? ScenarioColors.danger
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Customers',
                    value: '${row.customersServed}',
                    hint:
                        '${row.messagesSent} '
                        '${row.messagesSent == 1 ? 'message' : 'messages'} sent',
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Confirmed orders',
                    value: '${row.ordersConfirmed}',
                    hint: row.ordersConfirmed > 0
                        ? '${row.confirmedOrderValue} ${row.currency}'
                        : '${row.ordersRecorded} recorded, none confirmed',
                  ),
                ),
              ],
            ),

            if (row.platforms.isNotEmpty) ...[
              const SizedBox(height: Space.lg),
              Text(
                'BY PLATFORM',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Space.sm),
              for (final platform in row.platforms)
                _PlatformBar(platform: platform, max: _maxMessages),
            ],

            const SizedBox(height: Space.lg),
            HoursPanel(hours: row.hours),

            const SizedBox(height: Space.md),
            const Divider(height: 1),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.md,
              runSpacing: Space.xs,
              children: [
                _Footnote(
                  icon: Icons.forum_outlined,
                  label: '${row.conversationsHandled} handled',
                ),
                _Footnote(
                  icon: Icons.task_alt,
                  label: '${row.conversationsResolved} resolved',
                ),
                _Footnote(
                  icon: Icons.timer_outlined,
                  label:
                      'First reply '
                      '${formatDuration(row.firstResponseAverageSeconds)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int get _maxMessages => row.platforms.fold<int>(
    1,
    (max, p) => p.messages > max ? p.messages : max,
  );
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.hint,
    this.tone,
  });

  final String label;
  final String value;
  final String? hint;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: tone,
          ),
        ),
        if (hint != null)
          Text(
            hint!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
      ],
    );
  }
}

class _PlatformBar extends StatelessWidget {
  const _PlatformBar({required this.platform, required this.max});

  final PlatformVolume platform;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ConversationBadges.providerLabel(context, platform.provider),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                '${platform.messages} msg · ${platform.customers} '
                '${platform.customers == 1 ? 'customer' : 'customers'}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: platform.messages / max,
              minHeight: 5,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hours worked, or an honest statement that they were not recorded.
///
/// `hasSessionData` is false for any window before the availability log
/// started. Rendering "0h" there would be a claim about attendance rather than
/// an admission of a gap in measurement.
class HoursPanel extends StatelessWidget {
  const HoursPanel({required this.hours, super.key});

  final HoursBreakdown hours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!hours.hasSessionData) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HOURS',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              'Not recorded for this period.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    final adherence = hours.adherence;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'HOURS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (adherence != null)
                StatusBadge(
                  label: '${(adherence * 100).round()}% adherence',
                  tone: adherence >= 0.9
                      ? BadgeTone.success
                      : adherence >= 0.7
                      ? BadgeTone.warning
                      : BadgeTone.danger,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          _HoursRow(
            label: 'Online',
            value: formatHours(hours.onlineSeconds),
            bold: true,
          ),
          if (hours.breakSeconds > 0)
            _HoursRow(
              label: 'On break',
              value: formatHours(hours.breakSeconds),
            ),
          if (hours.awaySeconds > 0)
            _HoursRow(label: 'Away', value: formatHours(hours.awaySeconds)),
          const Divider(height: Space.lg),
          _HoursRow(
            label: 'Scheduled',
            value: hours.scheduledSeconds > 0
                ? formatHours(hours.scheduledSeconds)
                : 'No shifts set',
          ),
        ],
      ),
    );
  }
}

class _HoursRow extends StatelessWidget {
  const _HoursRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.textTheme.labelSmall?.color),
        const SizedBox(width: 3),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
