import '../../../core/widgets/status_chip.dart';
import '../../../models/interview_model.dart';
import '../../../models/quiz_model.dart';
import '../../applications/presentation/application_display.dart'
    show cleanDisplayText;

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

/// The single attendance-detail field relevant to an interview type (Phase
/// Final-QA-1) — phone -> contact phone, online -> meeting link, onsite ->
/// location. Shared by the Organization and Student detail screens so the
/// label/value pairing is defined once, not duplicated per screen.
String interviewContactDetailLabel(String interviewType) {
  switch (interviewType) {
    case 'phone':
      return 'Contact Phone';
    case 'online':
      return 'Meeting Link';
    case 'onsite':
      return 'Location';
    default:
      return 'Contact Detail';
  }
}

/// The relevant detail's cleaned value for [interview], or `null` if it
/// isn't set — a legacy interview scheduled before Phase Final-QA-1 (or one
/// with no relevant detail for any other reason) — the caller decides the
/// "Not specified" fallback text.
String? interviewContactDetailValue(InterviewModel interview) {
  switch (interview.interviewType) {
    case 'phone':
      return cleanDisplayText(interview.contactPhone);
    case 'online':
      return cleanDisplayText(interview.meetingLink);
    case 'onsite':
      return cleanDisplayText(interview.location);
    default:
      return null;
  }
}

/// User-facing labels for every documented `quiz.status` value.
const quizStatusLabels = {'draft': 'Draft', 'published': 'Published'};

AppStatusType quizStatusChipType(String status) {
  switch (status) {
    case 'published':
      return AppStatusType.success;
    case 'draft':
    default:
      return AppStatusType.warning;
  }
}

/// Phase 10A.4B addendum (section 12) — labels for
/// `AssessmentModel.quizTimingStatus`/`QuizCandidateResultModel.timingStatus`,
/// a derived-only value the backend computes fresh on every request (never
/// a stored enum — see `Assessment::quizTimingStatus()`, backend).
const quizTimingStatusLabels = {
  'upcoming': 'Upcoming',
  'available': 'Available',
  'in_progress': 'In Progress',
  'submitted': 'Submitted',
  'deadline_passed': 'Deadline Passed',
};

/// Phase 10A.4B addendum — a human-readable summary of a shared Quiz
/// template's candidate-availability policy (e.g. "2 days after
/// assignment at 10:00, 48-hour window"), for the Organization's own quiz
/// management UI. `quiz.availabilityDelayDays`/`availabilityTime`/
/// `submissionWindowHours` are only ever set on a template Quiz — this is
/// never called for a legacy per-candidate Quiz.
String describeAvailabilityPolicy(QuizModel quiz) {
  final delayDays = quiz.availabilityDelayDays;
  final time = quiz.availabilityTime;
  final windowHours = quiz.submissionWindowHours;
  if (delayDays == null || time == null || windowHours == null) {
    return 'Not configured yet';
  }

  final displayTime = _describeTimeOfDay(time);
  final delayLabel = delayDays == 0
      ? 'the day of assignment'
      : '$delayDays day${delayDays == 1 ? '' : 's'} after assignment';

  return '$delayLabel at $displayTime, $windowHours-hour window';
}

/// `"HH:MM"` (24-hour, as stored) into a friendlier `"h:mm AM/PM"` label.
/// Falls back to the raw value if it doesn't parse as expected — this is
/// display-only, never used for any real time computation.
String _describeTimeOfDay(String time) {
  final parts = time.split(':');
  if (parts.length < 2) return time;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return time;

  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  final displayMinute = minute.toString().padLeft(2, '0');
  return '$displayHour:$displayMinute $period';
}

/// User-facing labels for every documented `question.type` value.
const questionTypeLabels = {
  'multiple_choice': 'Multiple Choice',
  'true_false': 'True / False',
};
