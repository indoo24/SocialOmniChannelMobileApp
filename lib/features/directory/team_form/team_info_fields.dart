/// The team form's first section: name, description, language and colour.
///
/// Every value here is a plain `TeamWrite` field — `name` (≤120, required),
/// `description`, `language` (free text, ≤10) and `color` (≤7). The backend
/// keeps no list of languages, so language stays a short code typed in, as
/// on the web; colour is picked from swatches or typed as `#RRGGBB`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/l10n_extensions.dart';

/// The web form's default for a new team.
const defaultTeamColor = '#6366f1';

/// Swatches offered in the picker. The default comes first; a team's own
/// colour that is not here is still shown and kept.
const teamColorSwatches = [
  defaultTeamColor,
  '#0ea5e9',
  '#14b8a6',
  '#0f766e',
  '#22c55e',
  '#eab308',
  '#f97316',
  '#ef4444',
  '#ec4899',
  '#a855f7',
  '#64748b',
  '#1e293b',
];

final _hexPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

bool isValidTeamColor(String value) => _hexPattern.hasMatch(value.trim());

/// The colour [hex] names, or null when it is not `#RRGGBB`.
Color? parseTeamColor(String hex) {
  final value = hex.trim();
  if (!isValidTeamColor(value)) return null;
  return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
}

class TeamInfoFields extends StatelessWidget {
  const TeamInfoFields({
    required this.name,
    required this.description,
    required this.language,
    required this.color,
    required this.onColorChanged,
    required this.enabled,
    this.nameKey,
    this.errors = const {},
    super.key,
  });

  final TextEditingController name;
  final TextEditingController description;
  final TextEditingController language;
  final String color;
  final ValueChanged<String> onColorChanged;
  final bool enabled;

  /// Lets the form scroll the name field into view when it is invalid.
  final Key? nameKey;

  /// Messages keyed by `TeamWrite` field name, shown under that field.
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: nameKey,
          child: TextField(
            key: const ValueKey('teamFormName'),
            controller: name,
            enabled: enabled,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.teamNameFieldLabel,
              hintText: l10n.teamFormNamePlaceholder,
              errorText: errors['name'],
              errorMaxLines: 3,
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          key: const ValueKey('teamFormDescription'),
          controller: description,
          enabled: enabled,
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.descriptionFieldLabel,
            hintText: l10n.teamFormDescriptionPlaceholder,
            alignLabelWithHint: true,
            errorText: errors['description'],
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: Space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('teamFormLanguage'),
                controller: language,
                enabled: enabled,
                maxLength: 10,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.languageLabel,
                  hintText: 'ar',
                  helperText: l10n.teamFormLanguageHelper,
                  helperMaxLines: 2,
                  errorText: errors['language'],
                  errorMaxLines: 3,
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: _ColorField(
                value: color,
                enabled: enabled,
                error: errors['color'],
                onChanged: onColorChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Looks like the other fields; opens [showTeamColorPicker] on tap.
class _ColorField extends StatelessWidget {
  const _ColorField({
    required this.value,
    required this.enabled,
    required this.error,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final String? error;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final swatch = parseTeamColor(value);
    return Semantics(
      button: true,
      label: '${l10n.colorFieldLabel}: $value',
      child: InkWell(
        key: const ValueKey('teamFormColor'),
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: !enabled
            ? null
            : () async {
                final picked = await showTeamColorPicker(context, value);
                if (picked != null) onChanged(picked);
              },
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            labelText: l10n.colorFieldLabel,
            enabled: enabled,
            errorText: error,
            errorMaxLines: 3,
          ),
          child: Row(
            children: [
              _Swatch(color: swatch, size: 20),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  value.isEmpty ? '—' : value,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.size, this.selected});

  final Color? color;
  final double size;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill ?? scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected == true
              ? scheme.onSurface
              : scheme.outlineVariant.withValues(alpha: 0.8),
          width: selected == true ? 2.5 : 1,
        ),
      ),
      child: selected == true && fill != null
          ? Icon(
              Icons.check,
              size: size * 0.55,
              color:
                  ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            )
          : null,
    );
  }
}

/// Swatches plus a `#RRGGBB` field. Resolves to the chosen colour, or null
/// when dismissed.
Future<String?> showTeamColorPicker(BuildContext context, String current) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TeamColorDialog(initial: current),
  );
}

class _TeamColorDialog extends StatefulWidget {
  const _TeamColorDialog({required this.initial});

  final String initial;

  @override
  State<_TeamColorDialog> createState() => _TeamColorDialogState();
}

class _TeamColorDialogState extends State<_TeamColorDialog> {
  late final _hex = TextEditingController(
    text: widget.initial.isEmpty ? defaultTeamColor : widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _apply() {
    final value = _hex.text.trim();
    if (!isValidTeamColor(value)) {
      setState(() => _error = context.l10n.teamFormColorInvalid);
      return;
    }
    Navigator.of(context).pop(value.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = _hex.text.trim().toLowerCase();
    final swatches = [
      ...teamColorSwatches,
      if (isValidTeamColor(widget.initial) &&
          !teamColorSwatches.contains(widget.initial.toLowerCase()))
        widget.initial.toLowerCase(),
    ];
    return AlertDialog(
      title: Text(l10n.teamFormColorPickerTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final hex in swatches)
                  Semantics(
                    button: true,
                    selected: hex == current,
                    label: l10n.teamFormColorSwatch(hex),
                    child: InkWell(
                      key: ValueKey('teamColorSwatch_$hex'),
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() {
                        _hex.text = hex;
                        _error = null;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xxs),
                        child: _Swatch(
                          color: parseTeamColor(hex),
                          size: 36,
                          selected: hex == current,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.lg),
            TextField(
              key: const ValueKey('teamColorHex'),
              controller: _hex,
              maxLength: 7,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
              ],
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _apply(),
              decoration: InputDecoration(
                labelText: l10n.teamFormColorHexLabel,
                errorText: _error,
                errorMaxLines: 2,
                counterText: '',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: _Swatch(color: parseTeamColor(current), size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('teamColorApply'),
          onPressed: _apply,
          child: Text(l10n.teamFormColorApply),
        ),
      ],
    );
  }
}
