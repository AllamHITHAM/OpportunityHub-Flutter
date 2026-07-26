import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../models/opportunity_model.dart';

/// User-facing labels for every documented `opportunity_type` value.
/// Shared between the list, details, and form screens so the enum values
/// and their labels are defined in exactly one place.
const opportunityTypeLabels = {
  'job': 'Job',
  'internship': 'Internship',
  'volunteer': 'Volunteer',
  'scholarship': 'Scholarship',
  'competition': 'Competition',
};

const employmentTypeLabels = {
  'full_time': 'Full Time',
  'part_time': 'Part Time',
  'contract': 'Contract',
};

const workModeLabels = {
  'remote': 'Remote',
  'hybrid': 'Hybrid',
  'onsite': 'Onsite',
};

const experienceLevelLabels = {
  'no_experience': 'No Experience',
  'junior': 'Junior',
  'mid': 'Mid',
  'senior': 'Senior',
  'expert': 'Expert',
};

const educationLevelLabels = {
  'high_school': 'High School',
  'diploma': 'Diploma',
  'bachelor': "Bachelor's",
  'master': "Master's",
  'phd': 'PhD',
};

const statusLabels = {'draft': 'Draft', 'open': 'Open', 'closed': 'Closed'};

AppStatusType statusChipType(String status) {
  switch (status) {
    case 'open':
      return AppStatusType.success;
    case 'closed':
      return AppStatusType.neutral;
    case 'draft':
      return AppStatusType.warning;
    default:
      return AppStatusType.neutral;
  }
}

/// Formats an opportunity's salary range for display — shared between the
/// organization and student details screens rather than duplicated.
String formatSalaryRange(OpportunityModel opportunity) {
  final min = opportunity.salaryMin;
  final max = opportunity.salaryMax;
  if (min == null && max == null) return 'Not specified';
  if (min != null && max != null) {
    return '${min.toStringAsFixed(0)} - ${max.toStringAsFixed(0)}';
  }
  return (min ?? max)!.toStringAsFixed(0);
}

/// A label/value row used on the opportunity details "Details" card —
/// shared between the organization and student details screens rather than
/// duplicated.
class OpportunityDetailRow extends StatelessWidget {
  const OpportunityDetailRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
