import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/candidate_model.dart';
import '../../../models/candidate_skill_model.dart';
import '../../../models/location_model.dart';
import '../../../models/match_breakdown_model.dart';
import '../../../models/recommended_candidate_model.dart';
import '../../../providers/conversations_provider.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../../routes/app_routes.dart';
import '../../applications/presentation/application_display.dart';
import '../../opportunities/presentation/opportunity_display.dart';

const _maxContentWidth = 700.0;
const _twoColumnBreakpoint = 480.0;

/// A read-only view of one candidate's real profile fields (Phase O8.1,
/// enriched by the Organization Candidate Profile Enrichment phase) --
/// built from whichever source screen "View Profile" was reached from
/// ([CandidateModel] in the Talent Directory, or [RecommendedCandidateModel]
/// in Recommended Candidates). Carries only real, already
/// legally-exposed fields.
///
/// [applicationId]/[phone]/[email] are the same application_id-gated
/// signal both source models already carry (see [CandidateModel]'s own
/// doc comment) -- this view never widens that gate, it only forwards it.
/// [opportunityId]/[opportunityTitle]/[matchScore]/[matchBreakdown] are
/// only ever populated from [fromRecommended] -- reused verbatim from the
/// already-computed Recommendation result, never recalculated here (see
/// `_RecommendedForCard`). They are also what the optional "Message
/// Candidate" action needs: a concrete Opportunity context is required by
/// the backend to even attempt starting a conversation (see
/// `MessagingService::canOrganizationMessageStudent()`), so the profile
/// screen never offers messaging from a Talent Directory-only visit,
/// which carries none of this.
class CandidateProfileView {
  const CandidateProfileView({
    required this.id,
    required this.name,
    required this.university,
    required this.major,
    required this.graduationYear,
    required this.bio,
    required this.educationVerificationStatus,
    required this.currentLocation,
    required this.availableLocations,
    required this.skills,
    this.photoUrl,
    this.interestedIn,
    this.applicationId,
    this.phone,
    this.email,
    this.opportunityId,
    this.opportunityTitle,
    this.matchScore,
    this.matchBreakdown,
  });

  final int id;
  final String name;
  final String? university;
  final String? major;
  final int? graduationYear;
  final String? bio;
  final String educationVerificationStatus;
  final LocationModel? currentLocation;
  final List<LocationModel> availableLocations;
  final List<CandidateSkillModel> skills;

  /// Student Profile Photo: the candidate's uploaded profile photo, if
  /// any -- `null` keeps the existing initials-avatar fallback rendering.
  final String? photoUrl;

  /// Candidate Opportunity Preferences patch: only ever populated from
  /// the Talent Directory ([fromCandidate]) -- `null` from Recommended
  /// Candidates ([fromRecommended]), where every listed candidate is
  /// already implicitly interested in the exact Opportunity Type shown
  /// in that screen's own header, making a repeated chip here redundant.
  final List<String>? interestedIn;

  final int? applicationId;
  final String? phone;
  final String? email;

  final int? opportunityId;
  final String? opportunityTitle;
  final double? matchScore;
  final MatchBreakdownModel? matchBreakdown;

  /// Whether a real Opportunity context is known -- the one signal the
  /// "Message Candidate" action and the "Recommended for..." card both
  /// gate on.
  bool get hasOpportunityContext => opportunityId != null;

  factory CandidateProfileView.fromCandidate(CandidateModel candidate) {
    return CandidateProfileView(
      id: candidate.id,
      name: candidate.name,
      university: candidate.university,
      major: candidate.major,
      graduationYear: candidate.graduationYear,
      bio: candidate.bio,
      educationVerificationStatus: candidate.educationVerificationStatus,
      currentLocation: candidate.currentLocation,
      availableLocations: candidate.availableLocations,
      skills: candidate.skills,
      photoUrl: candidate.photoUrl,
      interestedIn: candidate.interestedIn,
      applicationId: candidate.applicationId,
      phone: candidate.phone,
      email: candidate.email,
    );
  }

  factory CandidateProfileView.fromRecommended(
    RecommendedCandidateModel candidate, {
    required int opportunityId,
    String? opportunityTitle,
  }) {
    return CandidateProfileView(
      id: candidate.id,
      name: candidate.name,
      university: candidate.university,
      major: candidate.major,
      graduationYear: candidate.graduationYear,
      bio: candidate.bio,
      educationVerificationStatus: candidate.educationVerificationStatus,
      currentLocation: candidate.currentLocation,
      availableLocations: candidate.availableLocations,
      skills: candidate.skills,
      photoUrl: candidate.photoUrl,
      applicationId: candidate.applicationId,
      phone: candidate.phone,
      email: candidate.email,
      opportunityId: opportunityId,
      opportunityTitle: opportunityTitle,
      matchScore: candidate.matchScore,
      matchBreakdown: candidate.matchBreakdown,
    );
  }
}

/// A read-only Organization-facing Candidate Profile -- a professional
/// recruiter profile (Organization Candidate Profile Enrichment phase),
/// reached from "View Profile" in either the Talent Directory or
/// Recommended Candidates. No route-addressable backend fetch exists for
/// a single candidate by ID, so [candidate] is passed in directly from the
/// already-loaded list the Organization was just browsing. A `null`
/// [candidate] (a direct URL visit/refresh with no `extra`) renders a
/// graceful empty state rather than crashing.
///
/// Section order follows the phase spec exactly: Header, Career
/// Interests, Professional & Academic Information, Location & Work
/// Availability, Skills, CV, Education Verification, Contact. There is no
/// AI CV Experience Snapshot section -- that feature isn't built anywhere
/// in this app yet (confirmed by audit), and the spec explicitly says not
/// to build it in this phase.
class OrganizationCandidateProfileScreen extends StatelessWidget {
  const OrganizationCandidateProfileScreen({super.key, this.candidate});

  final CandidateProfileView? candidate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Candidate Profile'),
        actions: const [ThemeToggleSurface()],
      ),
      body: SafeArea(
        child: candidate == null
            ? const AppEmptyView(
                icon: Icons.person_off_outlined,
                title: 'Candidate Not Found',
                message: 'This candidate profile is no longer available.',
              )
            : _buildBody(context, candidate!),
      ),
    );
  }

  Widget _buildBody(BuildContext context, CandidateProfileView candidate) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: width >= _twoColumnBreakpoint
                ? AppSpacing.xl
                : AppSpacing.screenHorizontal,
            vertical: AppSpacing.md,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: _ProfileEntrance(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProfileHeaderCard(candidate: candidate),
                    if (candidate.hasOpportunityContext) ...[
                      const SizedBox(height: AppSpacing.md),
                      _RecommendedForCard(candidate: candidate),
                    ],
                    if (candidate.interestedIn != null &&
                        candidate.interestedIn!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ProfileInterestsCard(candidate: candidate),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    _ProfessionalAcademicCard(candidate: candidate, width: width),
                    const SizedBox(height: AppSpacing.md),
                    _LocationAvailabilityCard(candidate: candidate),
                    if (candidate.skills.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ProfileSkillsCard(candidate: candidate),
                    ],
                    if (candidate.applicationId != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _CvCard(candidate: candidate),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    _EducationVerificationCard(candidate: candidate),
                    if (candidate.applicationId != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ContactCard(candidate: candidate),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileEntrance extends StatelessWidget {
  const _ProfileEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context, AppMotion.slow);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.entrance,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({required this.candidate});

  final CandidateProfileView candidate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitleParts = [
      if (candidate.major != null) candidate.major!,
      if (candidate.university != null) candidate.university!,
      if (candidate.graduationYear != null)
        'Class of ${candidate.graduationYear}',
    ];

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppAvatar(imageUrl: candidate.photoUrl, name: candidate.name, size: 56),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(candidate.name, style: textTheme.headlineSmall),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitleParts.join(' · '),
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section 12/21 of the phase spec: when opened from Recommended
/// Candidates with a known Opportunity context, shows "Recommended for
/// [Title] · Match X%" plus an expandable "View Match Details" (reusing
/// the already-computed [MatchBreakdownModel], never recalculating) and
/// the optional "Message Candidate" action. Never shown from a Talent
/// Directory-only visit -- see [CandidateProfileView.hasOpportunityContext].
class _RecommendedForCard extends StatefulWidget {
  const _RecommendedForCard({required this.candidate});

  final CandidateProfileView candidate;

  @override
  State<_RecommendedForCard> createState() => _RecommendedForCardState();
}

class _RecommendedForCardState extends State<_RecommendedForCard> {
  bool _expanded = false;

  Future<void> _message(BuildContext context) async {
    final provider = context.read<ConversationsProvider>();
    final conversationId = await provider.startConversation(
      studentId: widget.candidate.id,
      opportunityId: widget.candidate.opportunityId!,
    );
    if (!context.mounted) return;

    if (conversationId != null) {
      context.push(AppRoutes.organizationConversation(conversationId));
    } else if (provider.startErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.startErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final candidate = widget.candidate;
    final isStarting = context.watch<ConversationsProvider>().isStartingConversation;

    return AppCard(
      borderColor: AppColors.primaryLight,
      backgroundColor: AppColors.primaryContainer,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Recommended for ${candidate.opportunityTitle ?? 'this opportunity'}',
                      style: textTheme.titleSmall,
                    ),
                    if (candidate.matchScore != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Match ${candidate.matchScore!.round()}%',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (candidate.matchBreakdown != null) ...[
            const SizedBox(height: AppSpacing.xs),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Text(
                    _expanded ? 'Hide Match Details' : 'View Match Details',
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.primaryDark,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: AppSpacing.xs),
              _MatchBreakdownSummary(breakdown: candidate.matchBreakdown!),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: 'Message Candidate',
            icon: Icons.chat_bubble_outline_rounded,
            isLoading: isStarting,
            onPressed: () => _message(context),
          ),
        ],
      ),
    );
  }
}

/// A compact, real factor list built entirely from [breakdown] -- never a
/// recalculation, just the numbers the backend already computed (mirrors
/// `OrganizationRecommendedCandidatesScreen`'s own `_WhyMatchExpansion`,
/// kept intentionally simpler here since this is a supplementary context
/// card, not the primary comparison surface).
class _MatchBreakdownSummary extends StatelessWidget {
  const _MatchBreakdownSummary({required this.breakdown});

  final MatchBreakdownModel breakdown;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rows = <String>[
      if (breakdown.skillsMatchScore != null)
        'Skills: ${breakdown.skillsMatchScore!.round()}% '
            '(${breakdown.skillsWeight ?? 0} pts weight)',
      if (breakdown.majorMatchScore != null)
        'Major: ${breakdown.majorMatchScore!.round()}% '
            '(${breakdown.majorWeight ?? 0} pts weight)',
      if (breakdown.locationMatchScore != null)
        'Location: ${breakdown.locationMatchScore!.round()}% '
            '(${breakdown.locationWeight ?? 0} pts weight)',
    ];

    if (rows.isEmpty) {
      return Text(
        'No scoring factors were configured for this opportunity.',
        style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              row,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// "Career Interests" -- the candidate's own canonical Opportunity Type
/// preference (Candidate Opportunity Preferences patch), Talent Directory
/// only (see [CandidateProfileView.interestedIn]'s own doc comment for
/// why Recommended Candidates never populates this).
class _ProfileInterestsCard extends StatelessWidget {
  const _ProfileInterestsCard({required this.candidate});

  final CandidateProfileView candidate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Career Interests'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final type in candidate.interestedIn!)
                StatusChip(
                  label: opportunityTypeLabels[type] ?? type,
                  type: AppStatusType.info,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Professional & Academic Information" (spec item 4): University,
/// Major, Graduation Year, Bio. Education Verification status now has its
/// own separate section further down (see [_EducationVerificationCard]),
/// matching the phase spec's own section-order list exactly.
class _ProfessionalAcademicCard extends StatelessWidget {
  const _ProfessionalAcademicCard({required this.candidate, required this.width});

  final CandidateProfileView candidate;
  final double width;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fields = [
      DetailField('University', candidate.university ?? 'Not specified'),
      DetailField('Major', candidate.major ?? 'Not specified'),
      DetailField(
        'Graduation Year',
        candidate.graduationYear?.toString() ?? 'Not specified',
      ),
    ];
    final bio = cleanDisplayText(candidate.bio);

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Professional & Academic Information'),
          const SizedBox(height: AppSpacing.xs),
          DetailGrid(
            fields: fields,
            width: width,
            twoColumnBreakpoint: _twoColumnBreakpoint,
          ),
          if (bio != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Bio',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(bio, style: textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// "Location & Work Availability" (spec item 6): the Student's own
/// current/home Location and their selected Available Work Locations --
/// always canonical names from the Location Catalog, never raw IDs, and
/// truthful "Not provided"/"No work locations provided" fallbacks rather
/// than a blank section.
class _LocationAvailabilityCard extends StatelessWidget {
  const _LocationAvailabilityCard({required this.candidate});

  final CandidateProfileView candidate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Location & Work Availability'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Current Location',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            candidate.currentLocation?.canonicalName ?? 'Not provided',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Available Work Locations',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          candidate.availableLocations.isEmpty
              ? Text(
                  'No work locations provided',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    for (final location in candidate.availableLocations)
                      StatusChip(
                        label: location.canonicalName,
                        type: AppStatusType.neutral,
                        compact: true,
                      ),
                  ],
                ),
        ],
      ),
    );
  }
}

class _ProfileSkillsCard extends StatelessWidget {
  const _ProfileSkillsCard({required this.candidate});

  final CandidateProfileView candidate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Skills'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final skill in candidate.skills)
                StatusChip(
                  label: '${skill.name} (${skill.evidenceLabel})',
                  type: skill.isCvSupported
                      ? AppStatusType.info
                      : AppStatusType.neutral,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "CV" (spec item 8) -- only ever rendered when [CandidateProfileView.applicationId]
/// is real, the same application_id-gated authorization signal the
/// candidate row already carried. Reuses the exact same secure,
/// ownership-checked backend endpoint
/// (`Organization\ApplicationController::downloadCv()`) via the existing
/// `OrganizationApplicationsProvider.downloadCv()` -- there is no separate
/// "default CV by student ID" endpoint (audited: none exists), so this
/// intentionally shows the one real CV attached to *this* Application,
/// never a fabricated "default CV" concept. Matches
/// `OrganizationApplicationDetailsScreen`'s own v1 "fetch bytes, confirm
/// size" behavior rather than inventing a second CV-viewing UX here.
class _CvCard extends StatefulWidget {
  const _CvCard({required this.candidate});

  final CandidateProfileView candidate;

  @override
  State<_CvCard> createState() => _CvCardState();
}

class _CvCardState extends State<_CvCard> {
  Future<void> _viewCv(BuildContext context) async {
    final provider = context.read<OrganizationApplicationsProvider>();
    final bytes = await provider.downloadCv(widget.candidate.applicationId!);
    if (!context.mounted) return;

    if (bytes != null) {
      final kb = (bytes.length / 1024).toStringAsFixed(0);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CV downloaded ($kb KB)')));
    } else if (provider.cvDownloadErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.cvDownloadErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final applicationId = widget.candidate.applicationId!;
    final isDownloading = context
        .watch<OrganizationApplicationsProvider>()
        .isDownloadingCv(applicationId);

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'CV'),
          const SizedBox(height: AppSpacing.xs),
          SecondaryButton(
            label: 'View CV',
            icon: Icons.description_outlined,
            isLoading: isDownloading,
            onPressed: () => _viewCv(context),
          ),
        ],
      ),
    );
  }
}

class _EducationVerificationCard extends StatelessWidget {
  const _EducationVerificationCard({required this.candidate});

  final CandidateProfileView candidate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Education Verification'),
          const SizedBox(height: AppSpacing.xs),
          StatusChip(
            label: educationVerificationStatusLabel(
              candidate.educationVerificationStatus,
            ),
            type: candidate.educationVerificationStatus == 'verified'
                ? AppStatusType.success
                : AppStatusType.neutral,
            compact: true,
          ),
        ],
      ),
    );
  }
}

/// "Contact Information" (spec item 10) -- phone/email, only ever
/// rendered alongside a real [CandidateProfileView.applicationId]. Never
/// exposed from a general Talent Directory visit, preserving
/// `CandidateController`'s long-standing documented privacy guarantee for
/// that context.
class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.candidate});

  final CandidateProfileView candidate;

  @override
  Widget build(BuildContext context) {
    final email = cleanDisplayText(candidate.email);
    final phone = cleanDisplayText(candidate.phone);

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Contact'),
          const SizedBox(height: AppSpacing.xs),
          _ContactRow(
            icon: Icons.email_outlined,
            label: email ?? 'Not provided',
          ),
          const SizedBox(height: AppSpacing.xs),
          _ContactRow(
            icon: Icons.phone_outlined,
            label: phone ?? 'Not provided',
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
