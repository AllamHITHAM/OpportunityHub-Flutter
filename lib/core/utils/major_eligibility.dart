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
/// (Phase 8B-3.2), used only for the Invite flow's UX (disabling an
/// ineligible Opportunity before the organization even tries to select
/// it) -- **never the actual authority**. The backend re-checks this same
/// rule server-side and is what actually blocks an ineligible invitation;
/// this exists purely to avoid a round trip for an outcome the UI can
/// already predict.
bool isCandidateEligibleForOpportunity(
  CandidateModel candidate,
  OpportunityModel opportunity,
) {
  final major = candidate.major;

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
