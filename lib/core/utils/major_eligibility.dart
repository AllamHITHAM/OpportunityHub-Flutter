import '../../models/candidate_model.dart';
import '../../models/opportunity_model.dart';

/// Mirrors the backend's `App\Support\MajorNormalizer` exactly (trim,
/// lowercase, collapse internal whitespace) -- deliberately minimal, no
/// fuzzy/semantic matching.
String normalizeMajor(String value) {
  final collapsed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return collapsed.toLowerCase();
}

/// Client-side mirror of `OpportunityEligibilityService::isStudentEligible()`
/// (Phase 8B-3.2) -- **never the actual authority**. The backend re-checks
/// this same rule server-side and is what actually blocks an ineligible
/// invitation/application; this exists purely so the UI can predict an
/// outcome it already knows without a round trip. Takes a bare [major]
/// string rather than a specific model so both the organization's Invite
/// flow ([isCandidateEligibleForOpportunity], via [CandidateModel.major])
/// and the student's own Opportunity Details screen (via
/// `StudentProfileModel.major`) share this one rule instead of each
/// re-implementing it.
bool isMajorEligibleForOpportunity(
  String? major,
  OpportunityModel opportunity,
) {
  if (opportunity.eligibleMajors.isNotEmpty) {
    if (major == null || major.trim().isEmpty) return false;
    final normalizedMajor = normalizeMajor(major);
    return opportunity.eligibleMajors.any(
      (eligible) => normalizeMajor(eligible) == normalizedMajor,
    );
  }

  final fieldOfStudy = opportunity.fieldOfStudy;
  if (fieldOfStudy != null && fieldOfStudy.trim().isNotEmpty) {
    if (major == null || major.trim().isEmpty) return false;
    return normalizeMajor(major) == normalizeMajor(fieldOfStudy);
  }

  return true;
}

/// Used only for the Invite flow's UX (disabling an ineligible Opportunity
/// before the organization even tries to select it) -- see
/// [isMajorEligibleForOpportunity] for the shared rule and the same
/// "never the actual authority" caveat.
bool isCandidateEligibleForOpportunity(
  CandidateModel candidate,
  OpportunityModel opportunity,
) {
  return isMajorEligibleForOpportunity(candidate.major, opportunity);
}
