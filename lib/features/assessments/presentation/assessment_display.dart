import '../../../core/widgets/status_chip.dart';

// Display helpers for Assessment/Interview data — kept separate from
// `application_display.dart`, which is for `application.status` labels
// only. Application, Assessment, and Interview each have their own status
// vocabulary; mixing them into one file/map would blur three genuinely
// different concerns together.

/// User-facing labels for every documented `assessment.type` value.
const assessmentTypeLabels = {'interview': 'Interview', 'quiz': 'Quiz'};

/// User-facing labels for every documented `assessment.status` value.
const assessmentStatusLabels = {
  'pending': 'Pending',
  'scheduled': 'Scheduled',
  'in_progress': 'In Progress',
  'completed': 'Completed',
  'declined': 'Declined',
  'cancelled': 'Cancelled',
};

/// User-facing labels for every documented `assessment.result` value.
/// `null` (no result yet) is handled by the caller, not here.
const assessmentResultLabels = {
  'pending': 'Pending',
  'passed': 'Passed',
  'failed': 'Failed',
  'waiting': 'Waiting',
};

AppStatusType assessmentStatusChipType(String status) {
  switch (status) {
    case 'completed':
      return AppStatusType.success;
    case 'declined':
    case 'cancelled':
      return AppStatusType.neutral;
    case 'scheduled':
    case 'in_progress':
      return AppStatusType.info;
    case 'pending':
    default:
      return AppStatusType.warning;
  }
}

/// User-facing labels for every documented `interview.interview_type`
/// value.
const interviewTypeLabels = {
  'onsite': 'Onsite',
  'online': 'Online',
  'phone': 'Phone',
};

/// User-facing labels for every documented `interview.status` value.
const interviewStatusLabels = {
  'scheduled': 'Scheduled',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
  'rescheduled': 'Rescheduled',
  'no_show': 'No Show',
};

/// User-facing labels for every documented `interview.decision` value.
const interviewDecisionLabels = {
  'pending': 'Pending',
  'passed': 'Passed',
  'failed': 'Failed',
  'waiting': 'Waiting',
};
