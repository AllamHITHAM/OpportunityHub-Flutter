import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// One real field/value pair for a [DetailGrid] — a plain label/value
/// tuple, not tied to any backend field name beyond what's already
/// available to the caller.
class DetailField {
  const DetailField(this.label, this.value);

  final String label;
  final String value;
}

/// One detail "cell" — label stacked above value, rather than
/// [core/widgets/app_widgets.dart]'s `OpportunityDetailRow`-style single
/// label-left/value-right line. First built (UI Phase O4.1) because
/// label/value pairs sitting on the *same* row, side by side in a
/// two-column grid, read as one merged sentence ("Location AA Field of
/// Study CE") — stacking each pair vertically inside its own cell removes
/// that ambiguity regardless of column count, so this is used for both the
/// 1- and 2-column layouts rather than switching styles per breakpoint.
class DetailCell extends StatelessWidget {
  const DetailCell(this.field, {super.key});

  final DetailField field;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          field.label,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          field.value,
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A width-aware grid of [DetailField] label/value pairs — a single
/// stacked column below [twoColumnBreakpoint], or paired rows above it
/// with a subtle vertical divider between the two [DetailCell]s so a short
/// value on one side never reads as running into the next label. An odd
/// trailing field spans the row alone rather than leaving a fabricated
/// empty second cell.
///
/// First built for Opportunity Details (UI Phase O4.1), extracted here so
/// Organization Application Details (UI Phase O6) can reuse the exact same
/// real widget instead of a second copy that could drift.
class DetailGrid extends StatelessWidget {
  const DetailGrid({
    super.key,
    required this.fields,
    required this.width,
    this.twoColumnBreakpoint = 600,
  });

  final List<DetailField> fields;
  final double width;
  final double twoColumnBreakpoint;

  @override
  Widget build(BuildContext context) {
    if (width < twoColumnBreakpoint) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            DetailCell(fields[i]),
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      final hasPair = i + 1 < fields.length;
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: AppSpacing.md));
      }
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: DetailCell(fields[i])),
              if (hasPair) ...[
                const SizedBox(width: AppSpacing.lg),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.divider,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: DetailCell(fields[i + 1])),
              ],
            ],
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}
