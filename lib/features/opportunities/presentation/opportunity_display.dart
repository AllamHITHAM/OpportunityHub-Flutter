import '../../../core/widgets/status_chip.dart';

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
