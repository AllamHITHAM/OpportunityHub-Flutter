import '../../../core/widgets/status_chip.dart';

/// User-facing labels for every documented `application.status` value.
/// Shared between the list and details screens so the enum values and
/// their labels are defined in exactly one place.
const applicationStatusLabels = {
  'pending': 'Pending',
  'reviewed': 'Reviewed',
  'shortlisted': 'Shortlisted',
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
