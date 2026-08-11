import '../../../core/widgets/status_chip.dart';

/// User-facing labels for every documented `application.status` value.
/// Shared between the list and details screens so the enum values and
/// their labels are defined in exactly one place.
const applicationStatusLabels = {
  'pending': 'Pending',
  'reviewed': 'Reviewed',
  'shortlisted': 'Shortlisted',
  'in_assessment': 'Under Assessment',
  // Phase 6C-0/6C-1: the organization has sent a final Offer and the
  // student's response is pending — see docs/BUSINESS_RULES.md (backend)
  // section 5/7b.
  'offer_sent': 'Offer Sent',
  // Legacy compatibility only — no code path writes this status for new
  // assessments any more (see docs/BUSINESS_RULES.md on the backend), but
  // existing records may still carry it, so it stays a real, labeled value
  // here rather than falling through to the raw status string.
  'interview_scheduled': 'Interview Scheduled',
  'accepted': 'Accepted',
  'rejected': 'Rejected',
  'withdrawn': 'Withdrawn',
};

AppStatusType applicationStatusChipType(String status) {
  switch (status) {
    case 'accepted':
      return AppStatusType.success;
    case 'rejected':
    case 'withdrawn':
      return AppStatusType.neutral;
    case 'shortlisted':
    case 'in_assessment':
    case 'offer_sent':
    case 'interview_scheduled':
      return AppStatusType.info;
    case 'pending':
    case 'reviewed':
    default:
      return AppStatusType.warning;
  }
}

/// Normalizes a piece of applicant/profile display text: `null`, empty,
/// and whitespace-only values are all treated as missing (`null`);
/// anything else is returned trimmed. Never mutates the model this value
/// came from — purely a display-time transform, applied wherever an
/// applicant's identity/profile fields are rendered.
String? cleanDisplayText(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
