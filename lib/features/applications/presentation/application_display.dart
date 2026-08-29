import 'package:flutter/material.dart';

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

/// The five real, non-terminal stages `application.status` can sit at
/// before an outcome is reached — UI Phase 4's shared vocabulary for both
/// the Applications list's pipeline overview and Application Details'
/// progress rail. `interview_scheduled` (legacy) folds into [assessment]:
/// it predates the current `in_assessment`/dedicated-Assessment model but
/// means the same thing an application is actively being assessed.
enum ApplicationPipelineStage { applied, review, shortlisted, assessment, offer }

const applicationPipelineStageLabels = {
  ApplicationPipelineStage.applied: 'Applied',
  ApplicationPipelineStage.review: 'Review',
  ApplicationPipelineStage.shortlisted: 'Shortlisted',
  ApplicationPipelineStage.assessment: 'Assessment',
  ApplicationPipelineStage.offer: 'Offer',
};

const applicationPipelineStageIcons = {
  ApplicationPipelineStage.applied: Icons.send_outlined,
  ApplicationPipelineStage.review: Icons.visibility_outlined,
  ApplicationPipelineStage.shortlisted: Icons.star_outline_rounded,
  ApplicationPipelineStage.assessment: Icons.quiz_outlined,
  ApplicationPipelineStage.offer: Icons.card_giftcard_outlined,
};

/// The pipeline stage [status] currently sits at, or `null` for a terminal
/// outcome (`accepted`/`rejected`/`withdrawn`) or any unrecognized value —
/// an outcome is never itself a "stage" (see [isTerminalApplicationStatus]).
ApplicationPipelineStage? pipelineStageForStatus(String status) {
  switch (status) {
    case 'pending':
      return ApplicationPipelineStage.applied;
    case 'reviewed':
      return ApplicationPipelineStage.review;
    case 'shortlisted':
      return ApplicationPipelineStage.shortlisted;
    case 'in_assessment':
    case 'interview_scheduled':
      return ApplicationPipelineStage.assessment;
    case 'offer_sent':
      return ApplicationPipelineStage.offer;
    default:
      return null;
  }
}

/// Whether [status] is a final outcome rather than an active recruitment
/// stage — `accepted`, `rejected`, or `withdrawn`. Deliberately distinct
/// from "[pipelineStageForStatus] returns null", since an unrecognized
/// future status would also return null without being a known outcome.
bool isTerminalApplicationStatus(String status) {
  return status == 'accepted' || status == 'rejected' || status == 'withdrawn';
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

/// User-facing labels for every `education_verification_status` value
/// (Phase 8B-1) an Organization may see on an applicant. "Verified" here
/// means an Admin reviewed the document and approved it -- never a direct
/// university/government check (see docs/BUSINESS_RULES.md).
const educationVerificationStatusLabels = {
  'not_submitted': 'Not Submitted',
  'pending': 'Pending Review',
  'verified': 'Verified',
  'rejected': 'Rejected',
};

String educationVerificationStatusLabel(String? status) {
  return educationVerificationStatusLabels[status] ?? 'Not Submitted';
}

/// User-facing labels for the deterministic match-analysis factors
/// (`App\Services\MatchingService`) — Skills, Major, and Location.
/// Deliberately never called "AI Score" anywhere in this app: the
/// underlying scoring is entirely rule-based and deterministic, never
/// AI/LLM-generated.
///
/// Opportunity Academic Matching Cleanup (v1.2) removed the original
/// Field/Major factor (compared `major` against the deprecated free-text
/// `field_of_study`) entirely. Recommendation Match: Major Must Contribute
/// to Total Score (v1.3) added a new Major factor back in its place,
/// computed from the Student's major against the Opportunity's canonical
/// Eligible Majors — never `field_of_study`, which remains unused by any
/// factor. Labeled `'major'`, not `'field'`, to avoid ever implying a
/// `field_of_study` dependency.
///
/// Candidate Opportunity Preferences + Final Recommendation Match Formula
/// (v2.0): Experience is removed entirely (no `'experience'` entry any
/// more) and Location takes its place, computed from the Opportunity's
/// canonical location against the Student's Available Work Locations —
/// `null`/"Not available" for a Remote Opportunity, where Location is
/// never considered at all.
const matchFactorLabels = {
  'skills': 'Skills Match',
  'major': 'Major Match',
  'location': 'Location Match',
};

/// Formats a 0–100 match factor score as a whole-number percentage, or
/// "Not available" when the backend genuinely couldn't score that factor
/// (missing student major, no opportunity skills, etc.) — never rendered
/// as a misleading 0%, since the backend itself distinguishes "scored
/// zero" from "not scoreable" (`null`).
String formatMatchScore(double? score) {
  if (score == null) return 'Not available';
  return '${score.toStringAsFixed(0)}%';
}
