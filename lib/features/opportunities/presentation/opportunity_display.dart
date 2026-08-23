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

/// How many eligible majors to name before collapsing the rest into a
/// "+N" suffix, so a long list never overflows its container.
const _maxNamedMajors = 2;

/// A short, honest summary of who an opportunity is open to — prefers the
/// explicit [OpportunityModel.eligibleMajors] list (Phase 8B-3.2) and
/// falls back to the legacy single [OpportunityModel.fieldOfStudy] only
/// when no explicit majors are set, mirroring the fallback documented on
/// the model itself. Returns `null` (render nothing) when neither is
/// present, rather than a fabricated "Open to all majors". Shared between
/// [OpportunityCard] and the student details screen rather than duplicated.
String? eligibilityLabel(OpportunityModel opportunity) {
  final majors = opportunity.eligibleMajors;
  if (majors.isNotEmpty) {
    final named = majors.take(_maxNamedMajors).join(', ');
    final remaining = majors.length - _maxNamedMajors;
    return remaining > 0 ? '$named, +$remaining more' : named;
  }
  if (opportunity.fieldOfStudy != null &&
      opportunity.fieldOfStudy!.trim().isNotEmpty) {
    return opportunity.fieldOfStudy;
  }
  return null;
}

/// How urgent an opportunity's application deadline is, purely a function
/// of real data (`applicationDeadline` vs. the current time) — never a
/// fabricated countdown.
enum DeadlineUrgency {
  /// No deadline set at all.
  none,

  /// The deadline has already passed.
  passed,

  /// 3 days or fewer remain.
  soon,

  /// More than 3 days remain.
  normal,
}

DeadlineUrgency deadlineUrgencyFor(DateTime? deadline, {DateTime? now}) {
  if (deadline == null) return DeadlineUrgency.none;
  final reference = now ?? DateTime.now();
  final daysLeft = deadline.difference(reference).inHours / 24;
  if (daysLeft < 0) return DeadlineUrgency.passed;
  if (daysLeft <= 3) return DeadlineUrgency.soon;
  return DeadlineUrgency.normal;
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
