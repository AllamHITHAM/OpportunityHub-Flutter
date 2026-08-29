import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../opportunities/presentation/opportunity_display.dart';

/// A multi-select field over the canonical Opportunity Type vocabulary
/// (`opportunityTypeLabels` — the exact same values/labels
/// `OpportunityModel.opportunityType` uses, never a second vocabulary) for
/// a Student's own "Interested In" preference (Candidate Opportunity
/// Preferences patch). Shared between Student Profile Setup (onboarding)
/// and Edit Profile so the chip layout/behavior is defined in exactly one
/// place.
///
/// Deliberately a plain [Wrap] of [FilterChip]s, not the searchable/
/// creatable pattern [AvailableLocationsField] uses — the vocabulary here
/// is small (5 values) and fixed (backend-validated `Rule::in`), so there
/// is nothing to search or create.
class InterestedInField extends StatelessWidget {
  const InterestedInField({
    super.key,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final Set<String> selected;
  final bool enabled;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final entry in opportunityTypeLabels.entries)
          FilterChip(
            label: Text(entry.value),
            selected: selected.contains(entry.key),
            onSelected: enabled ? (_) => onToggle(entry.key) : null,
          ),
      ],
    );
  }
}
