import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/education_verification_model.dart';
import '../../../providers/student_education_verification_provider.dart';
import '../../../routes/app_routes.dart';
import '../../cv/data/picked_cv_file.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import '../../cv/presentation/student_cv_screen.dart' show pickCvFileFromDevice;

const _tabletBreakpoint = 600.0;
const _desktopBreakpoint = 1200.0;

enum _ScreenTier { mobile, tablet, desktop }

_ScreenTier _tierFor(double width) {
  if (width >= _desktopBreakpoint) return _ScreenTier.desktop;
  if (width >= _tabletBreakpoint) return _ScreenTier.tablet;
  return _ScreenTier.mobile;
}

/// The four real statuses (`docs/BUSINESS_RULES.md` section 9b), and the
/// exact same human-readable labels `StudentProfileScreen`'s own
/// verification card already uses -- kept identical here so the two
/// screens never show conflicting wording for the same real state.
class _StatusMeta {
  const _StatusMeta(this.type, this.icon, this.label, this.explanation);

  final AppStatusType type;
  final IconData icon;
  final String label;
  final String explanation;
}

_StatusMeta _statusMetaFor(EducationVerificationModel verification) {
  if (verification.isVerified) {
    return const _StatusMeta(
      AppStatusType.success,
      Icons.verified_rounded,
      'Verified',
      'An administrator reviewed your document and confirmed it.',
    );
  }
  if (verification.isPending) {
    return const _StatusMeta(
      AppStatusType.warning,
      Icons.hourglass_top_rounded,
      'Pending Review',
      'Your document is awaiting review by a platform administrator.',
    );
  }
  if (verification.isRejected) {
    return const _StatusMeta(
      AppStatusType.error,
      Icons.cancel_outlined,
      'Rejected',
      "An administrator reviewed your document and couldn't verify it.",
    );
  }
  return const _StatusMeta(
    AppStatusType.neutral,
    Icons.school_outlined,
    'Not Submitted',
    "You haven't submitted your education verification yet.",
  );
}

/// A real filename for the View/Download actions -- built from the
/// student's own already-loaded institution name (real data), never an
/// invented one. The backend never stores the student's original filename
/// at all (see `EducationVerificationController::store()`), so there is
/// nothing more specific to show here truthfully.
String _documentFileName(EducationVerificationModel verification) {
  final institution = verification.institutionName;
  return institution == null || institution.isEmpty
      ? 'Education Verification.pdf'
      : '$institution - Education Verification.pdf';
}

/// The Student's own education-verification submission and status (Phase
/// 8). "Verified" means an Admin reviewed the uploaded document and
/// approved it -- not a direct university/government check; see
/// docs/BUSINESS_RULES.md. This is deliberately not an AI feature and uses
/// no AI-purple styling anywhere.
///
/// **Audited, deliberately preserved gaps:**
/// - The backend has no original-filename or file-size column for the
///   uploaded document (`EducationVerification` only ever stores a
///   generated UUID path) -- the document card below shows only real data
///   (submission date, status), never an invented filename/size.
/// - No notification is sent when an Admin reviews a submission (no
///   `Notification` write exists anywhere in `EducationVerificationController`)
///   -- the "what happens next" copy never claims one is.
/// - The backend technically allows resubmission while `pending` (not just
///   after `rejected`) -- see `docs/BUSINESS_RULES.md` section 9b. This
///   screen deliberately keeps the pending state read-only (as the
///   pre-existing implementation already did) rather than inventing a
///   "resubmit while under review" affordance; report this as a genuine
///   product choice, not a backend limitation.
/// - No drag-and-drop upload -- this app's file-picking architecture
///   (`pickCvFileFromDevice`) is click-to-select only on every platform;
///   adding a real Web drop-zone would be new platform-specific code this
///   phase doesn't introduce.
class StudentEducationVerificationScreen extends StatefulWidget {
  const StudentEducationVerificationScreen({
    super.key,
    this.pickDocumentFile = pickCvFileFromDevice,
  });

  /// Defaults to the same real platform file picker `StudentCvScreen`
  /// uses -- overridable so widget tests can simulate a file selection
  /// without a real platform channel.
  final Future<PickedCvFile?> Function() pickDocumentFile;

  @override
  State<StudentEducationVerificationScreen> createState() =>
      _StudentEducationVerificationScreenState();
}

class _StudentEducationVerificationScreenState
    extends State<StudentEducationVerificationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentEducationVerificationProvider>().load();
    });

    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _entranceController = AnimationController(
      vsync: this,
      duration: reducedMotion
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _viewDocument(EducationVerificationModel verification) async {
    final provider = context.read<StudentEducationVerificationProvider>();

    final success = await provider.viewDocument(_documentFileName(verification));
    if (!mounted) return;

    if (!success && provider.viewErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.viewErrorMessage!)));
    }
  }

  Future<void> _downloadDocument(EducationVerificationModel verification) async {
    final provider = context.read<StudentEducationVerificationProvider>();

    final success = await provider.downloadDocumentFile(_documentFileName(verification));
    if (!mounted) return;

    if (!success && provider.downloadErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.downloadErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentEducationVerificationProvider>();
    final tier = _tierFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Education Verification'),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(child: _buildBody(provider, tier)),
    );
  }

  Widget _buildBody(StudentEducationVerificationProvider provider, _ScreenTier tier) {
    final verification = provider.verification;

    if (provider.isLoading && verification == null) {
      return const _VerificationSkeleton();
    }

    if (provider.errorMessage != null && verification == null) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    if (verification == null) {
      // Neither loading, nor an error, nor a result yet -- the load
      // hasn't been kicked off (e.g. the very first frame).
      return const AppLoading();
    }

    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;
    final maxWidth = tier == _ScreenTier.desktop ? 1100.0 : 760.0;

    return RefreshIndicator(
      onRefresh: () => provider.load(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PageHeader(tier: tier, entranceController: _entranceController),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.lg,
                    horizontalPadding,
                    AppSpacing.xxl,
                  ),
                  child: _Stagger(
                    controller: _entranceController,
                    index: 1,
                    count: 3,
                    child: _VerificationLayout(
                      tier: tier,
                      provider: provider,
                      verification: verification,
                      pickFile: widget.pickDocumentFile,
                      onView: () => _viewDocument(verification),
                      onDownload: () => _downloadDocument(verification),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a section in as part of the staged entrance — a
/// private per-file copy of the same small helper other premium screens
/// this session define (see e.g. `StudentCvScreen`'s own doc comment on
/// why it's kept separate rather than shared).
class _Stagger extends StatelessWidget {
  const _Stagger({
    required this.controller,
    required this.index,
    required this.count,
    required this.child,
  });

  final AnimationController controller;
  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = count <= 1 ? 0.0 : index / count;
    final end = count <= 1 ? 1.0 : ((index + 1.4) / count).clamp(start, 1.0);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: AppMotion.entrance),
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// A compact page identity — plain primary color (not the `[primary,
/// aiAccent]` gradient `StudentCvScreen` uses): education verification is
/// entirely human Admin review, never an AI feature (see this file's own
/// top doc comment), so no AI-purple styling appears anywhere on this
/// screen.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.tier, required this.entranceController});

  final _ScreenTier tier;
  final AnimationController entranceController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryContainer.withValues(alpha: 0.5),
            AppColors.surface,
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppSpacing.lg,
          horizontalPadding,
          AppSpacing.md,
        ),
        child: _Stagger(
          controller: entranceController,
          index: 0,
          count: 3,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                  boxShadow: AppShadows.card,
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Education Verification',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Confirm your academic information to strengthen '
                      'your student profile.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The main two-column-on-desktop layout: status + details/document/form
/// on the left, process/profile/privacy on the right — stacked on
/// mobile/tablet.
class _VerificationLayout extends StatelessWidget {
  const _VerificationLayout({
    required this.tier,
    required this.provider,
    required this.verification,
    required this.pickFile,
    required this.onView,
    required this.onDownload,
  });

  final _ScreenTier tier;
  final StudentEducationVerificationProvider provider;
  final EducationVerificationModel verification;
  final Future<PickedCvFile?> Function() pickFile;
  final VoidCallback onView;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final left = _PrimaryColumn(
      provider: provider,
      verification: verification,
      pickFile: pickFile,
      onView: onView,
      onDownload: onDownload,
    );
    const right = _SecondaryColumn();

    if (tier != _ScreenTier.desktop) {
      return Column(
        children: [left, const SizedBox(height: AppSpacing.lg), right],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: left),
        const SizedBox(width: AppSpacing.lg),
        const Expanded(flex: 2, child: right),
      ],
    );
  }
}

class _PrimaryColumn extends StatelessWidget {
  const _PrimaryColumn({
    required this.provider,
    required this.verification,
    required this.pickFile,
    required this.onView,
    required this.onDownload,
  });

  final StudentEducationVerificationProvider provider;
  final EducationVerificationModel verification;
  final Future<PickedCvFile?> Function() pickFile;
  final VoidCallback onView;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusHero(verification: verification),
        const SizedBox(height: AppSpacing.md),
        _VerificationJourney(verification: verification),
        const SizedBox(height: AppSpacing.md),
        AnimatedSwitcher(
          duration: AppMotion.reduced(context, AppMotion.normal),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Column(
            key: ValueKey(verification.status),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (verification.isRejected) ...[
                _RejectionFeedbackCard(verification: verification),
                const SizedBox(height: AppSpacing.md),
              ],
              if (!verification.isNotSubmitted) ...[
                _VerificationDetailsCard(verification: verification),
                const SizedBox(height: AppSpacing.md),
                if (verification.isPending)
                  _PendingDocumentSection(
                    provider: provider,
                    verification: verification,
                    pickFile: pickFile,
                    onView: onView,
                    onDownload: onDownload,
                  )
                else
                  _DocumentCard(
                    submittedAt: verification.submittedAt,
                    isViewing: provider.isViewingDocument,
                    isDownloading: provider.isDownloading,
                    onView: onView,
                    onDownload: onDownload,
                  ),
              ],
              if (verification.isNotSubmitted || verification.isRejected) ...[
                if (!verification.isNotSubmitted) const SizedBox(height: AppSpacing.md),
                _RequirementsPanel(isResubmission: verification.isRejected),
                const SizedBox(height: AppSpacing.md),
                verification.isRejected
                    ? _SubmissionForm(
                        pickFile: pickFile,
                        prefillFrom: verification,
                        title: 'Resubmit Document',
                        submitLabel: 'Resubmit',
                        successMessage: 'Education verification submitted successfully',
                      )
                    : _SubmissionForm(
                        pickFile: pickFile,
                        title: 'Upload Academic Document',
                        submitLabel: 'Submit for Verification',
                        successMessage: 'Education verification submitted successfully',
                      ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.verification});

  final EducationVerificationModel verification;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final meta = _statusMetaFor(verification);

    return AppCard(
      borderColor: _accentBorderFor(meta.type),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: AppMotion.reduced(context, AppMotion.normal),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Container(
              key: ValueKey(verification.status),
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _iconBackgroundFor(meta.type),
              ),
              child: Icon(meta.icon, size: 20, color: _iconColorFor(meta.type)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        meta.label,
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  meta.explanation,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color? _accentBorderFor(AppStatusType type) {
    switch (type) {
      case AppStatusType.success:
        return AppColors.success.withValues(alpha: 0.25);
      case AppStatusType.warning:
        return AppColors.warning.withValues(alpha: 0.3);
      case AppStatusType.error:
        return AppColors.error.withValues(alpha: 0.25);
      default:
        return null;
    }
  }

  Color _iconBackgroundFor(AppStatusType type) {
    switch (type) {
      case AppStatusType.success:
        return AppColors.successBackground;
      case AppStatusType.warning:
        return AppColors.warningBackground;
      case AppStatusType.error:
        return AppColors.errorBackground;
      default:
        return AppColors.surfaceVariant;
    }
  }

  Color _iconColorFor(AppStatusType type) {
    switch (type) {
      case AppStatusType.success:
        return AppColors.success;
      case AppStatusType.warning:
        return AppColors.warning;
      case AppStatusType.error:
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }
}

/// A display-only stage in the [_VerificationJourney] -- never a new
/// backend status, never persisted, never implies review duration or
/// queue position. Purely a visual re-mapping of the four real statuses
/// already shown elsewhere on this page.
enum _JourneyStageState { upcoming, current, complete, rejected }

class _JourneyStage {
  const _JourneyStage(this.label, this.state);
  final String label;
  final _JourneyStageState state;
}

/// The exact real-status → journey-stage mapping (Phase 8.1):
/// - `not_submitted`: nothing complete yet; Submitted is the next real step.
/// - `pending`: Submitted complete, Admin Review current, Decision upcoming.
/// - `verified`: all three complete.
/// - `rejected`: Submitted + Admin Review complete, Decision shows the
///   real rejected outcome.
List<_JourneyStage> _journeyStagesFor(EducationVerificationModel verification) {
  if (verification.isVerified) {
    return const [
      _JourneyStage('Submitted', _JourneyStageState.complete),
      _JourneyStage('Admin Review', _JourneyStageState.complete),
      _JourneyStage('Decision', _JourneyStageState.complete),
    ];
  }
  if (verification.isRejected) {
    return const [
      _JourneyStage('Submitted', _JourneyStageState.complete),
      _JourneyStage('Admin Review', _JourneyStageState.complete),
      _JourneyStage('Decision', _JourneyStageState.rejected),
    ];
  }
  if (verification.isPending) {
    return const [
      _JourneyStage('Submitted', _JourneyStageState.complete),
      _JourneyStage('Admin Review', _JourneyStageState.current),
      _JourneyStage('Decision', _JourneyStageState.upcoming),
    ];
  }
  return const [
    _JourneyStage('Submitted', _JourneyStageState.current),
    _JourneyStage('Admin Review', _JourneyStageState.upcoming),
    _JourneyStage('Decision', _JourneyStageState.upcoming),
  ];
}

/// A compact, premium, display-only process visualization (Phase 8.1) --
/// see [_journeyStagesFor]'s own doc comment for the exact real-status
/// mapping. Purely explanatory; adds no new data source of its own.
class _VerificationJourney extends StatelessWidget {
  const _VerificationJourney({required this.verification});

  final EducationVerificationModel verification;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final stages = _journeyStagesFor(verification);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Verification Journey',
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedSwitcher(
            duration: AppMotion.reduced(context, AppMotion.normal),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Row(
              key: ValueKey(verification.status),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < stages.length; i++) ...[
                  if (i > 0)
                    _JourneyConnector(
                      active: stages[i - 1].state == _JourneyStageState.complete,
                    ),
                  _JourneyStageIndicator(stage: stages[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyConnector extends StatelessWidget {
  const _JourneyConnector({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(top: 15, left: 4, right: 4),
        child: AnimatedContainer(
          duration: AppMotion.reduced(context, AppMotion.normal),
          curve: AppMotion.standard,
          height: 2,
          decoration: BoxDecoration(
            color: active ? AppColors.success : AppColors.border,
            borderRadius: AppRadius.pillRadius,
          ),
        ),
      ),
    );
  }
}

class _JourneyStageIndicator extends StatelessWidget {
  const _JourneyStageIndicator({required this.stage});

  final _JourneyStage stage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final Color background;
    final Color foreground;
    final IconData? icon;

    switch (stage.state) {
      case _JourneyStageState.complete:
        background = AppColors.success;
        foreground = Colors.white;
        icon = Icons.check_rounded;
      case _JourneyStageState.current:
        background = AppColors.warning;
        foreground = Colors.white;
        icon = Icons.more_horiz_rounded;
      case _JourneyStageState.rejected:
        background = AppColors.error;
        foreground = Colors.white;
        icon = Icons.close_rounded;
      case _JourneyStageState.upcoming:
        background = AppColors.surfaceVariant;
        foreground = AppColors.textMuted;
        icon = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: AppMotion.reduced(context, AppMotion.normal),
          curve: AppMotion.standard,
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: icon != null
              ? Icon(icon, size: 16, color: foreground)
              : Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: foreground),
                ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        SizedBox(
          width: 76,
          child: Text(
            stage.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              fontWeight: stage.state == _JourneyStageState.current
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: stage.state == _JourneyStageState.upcoming
                  ? AppColors.textMuted
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _VerificationDetailsCard extends StatelessWidget {
  const _VerificationDetailsCard({required this.verification});

  final EducationVerificationModel verification;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verification Details',
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          OpportunityDetailRow(
            label: 'Institution',
            value: verification.institutionName ?? 'Not specified',
          ),
          OpportunityDetailRow(
            label: 'Degree / Program',
            value: verification.degreeOrProgram ?? 'Not specified',
          ),
          if (verification.submittedAt != null)
            OpportunityDetailRow(
              label: 'Submitted',
              value: formatDate(verification.submittedAt!),
            ),
          if (verification.isVerified && verification.reviewedAt != null)
            OpportunityDetailRow(
              label: 'Reviewed',
              value: formatDate(verification.reviewedAt!),
            ),
        ],
      ),
    );
  }
}

/// Pending-only (Phase 8.1): the document card plus a real "Replace
/// Document" action -- gated behind a confirmation dialog, then reveals
/// the exact same [_SubmissionForm] every other submission path uses,
/// pre-filled from the current pending values. Reuses
/// `StudentEducationVerificationProvider.submit` unchanged -- the backend
/// already allows replacing a `pending` submission (see this file's own
/// top doc comment); this only exposes that real capability in the UI.
class _PendingDocumentSection extends StatefulWidget {
  const _PendingDocumentSection({
    required this.provider,
    required this.verification,
    required this.pickFile,
    required this.onView,
    required this.onDownload,
  });

  final StudentEducationVerificationProvider provider;
  final EducationVerificationModel verification;
  final Future<PickedCvFile?> Function() pickFile;
  final VoidCallback onView;
  final VoidCallback onDownload;

  @override
  State<_PendingDocumentSection> createState() => _PendingDocumentSectionState();
}

class _PendingDocumentSectionState extends State<_PendingDocumentSection> {
  bool _isReplacing = false;

  Future<void> _confirmReplace() async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Replace submitted document?',
      message:
          'You already have a document waiting for review. The new '
          'document will replace the current submission for review.',
      confirmLabel: 'Continue',
      cancelLabel: 'Cancel',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isReplacing = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.reduced(context, AppMotion.normal),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: _isReplacing
          ? _SubmissionForm(
              key: const ValueKey('replace-form'),
              pickFile: widget.pickFile,
              prefillFrom: widget.verification,
              title: 'Replace Document',
              submitLabel: 'Replace Document',
              successMessage: 'Document replaced successfully.',
              onCancel: () => setState(() => _isReplacing = false),
              onSuccess: () {
                if (mounted) setState(() => _isReplacing = false);
              },
            )
          : Column(
              key: const ValueKey('document-view'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DocumentCard(
                  submittedAt: widget.verification.submittedAt,
                  isViewing: widget.provider.isViewingDocument,
                  isDownloading: widget.provider.isDownloading,
                  onView: widget.onView,
                  onDownload: widget.onDownload,
                ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: 'Replace Document',
                  icon: Icons.swap_horiz_rounded,
                  onPressed: _confirmReplace,
                ),
              ],
            ),
    );
  }
}

/// Real fields only — no invented original filename or file size (the
/// backend stores neither, see this file's own top doc comment).
class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.submittedAt,
    required this.isViewing,
    required this.isDownloading,
    required this.onView,
    required this.onDownload,
  });

  final DateTime? submittedAt;
  final bool isViewing;
  final bool isDownloading;
  final VoidCallback onView;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer,
                ),
                child: Icon(
                  Icons.picture_as_pdf_rounded,
                  size: 20,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Submitted Document',
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    // "PDF Document" is a real, certain fact (the backend
                    // only ever accepts `mimes:pdf`), never an invented
                    // filename -- see this file's own top doc comment on
                    // why no original filename/size is shown here.
                    Text(
                      [
                        'PDF Document',
                        if (submittedAt != null) 'Submitted ${formatDate(submittedAt!)}',
                      ].join(' · '),
                      style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 340;
              final viewButton = SecondaryButton(
                label: 'View Document',
                icon: Icons.visibility_outlined,
                height: 40,
                isLoading: isViewing,
                onPressed: isViewing ? null : onView,
              );
              final downloadButton = SecondaryButton(
                label: 'Download',
                icon: Icons.download_outlined,
                height: 40,
                isLoading: isDownloading,
                onPressed: isDownloading ? null : onDownload,
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    viewButton,
                    const SizedBox(height: AppSpacing.xs),
                    downloadButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: viewButton),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: downloadButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RejectionFeedbackCard extends StatelessWidget {
  const _RejectionFeedbackCard({required this.verification});

  final EducationVerificationModel verification;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reason = verification.rejectionReason;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.errorBackground,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.feedback_outlined, size: 18, color: AppColors.error),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  'Review Feedback',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            reason ?? 'No specific reason was provided.',
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// The submission requirements, truthfully limited to what
/// `StoreEducationVerificationRequest` actually validates.
class _RequirementsPanel extends StatelessWidget {
  const _RequirementsPanel({required this.isResubmission});

  final bool isResubmission;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.largeRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isResubmission ? "What You'll Need to Resubmit" : "What You'll Need",
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          const _RequirementRow(text: 'Your institution name and degree or program'),
          const _RequirementRow(text: 'A PDF document proving your enrollment or degree'),
          const _RequirementRow(text: 'File size up to 5 MB'),
        ],
      ),
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Truthful, status-driven explanation of what happens next — never a
/// promised review time, never a claimed notification (none is sent; see
/// this file's own top doc comment).
class _WhatHappensNextCard extends StatelessWidget {
  const _WhatHappensNextCard({required this.verification});

  final EducationVerificationModel verification;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final String message;

    if (verification.isVerified) {
      message =
          'Your education is verified. Organizations reviewing your '
          'applications can see this as a trust signal alongside your '
          'other profile information.';
    } else if (verification.isPending) {
      message =
          'Your document is waiting for review by a platform administrator. '
          'We don\'t send a notification when it\'s reviewed, so check back '
          'here for your updated status. Need to fix something? You can '
          'replace your document below before it\'s reviewed.';
    } else if (verification.isRejected) {
      message =
          "Review the feedback above, then resubmit an updated document "
          "whenever you're ready.";
    } else {
      message =
          'Submit your document below. A platform administrator will '
          'review it and your status here will update once they do.';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.infoBackground,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  'What Happens Next',
                  style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(message, style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ProfileConnectionCard extends StatelessWidget {
  const _ProfileConnectionCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Part of Your Profile',
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Your verification status also appears on your Student Profile.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: 'Back to Profile',
            icon: Icons.arrow_back_rounded,
            height: 40,
            onPressed: () => context.push(AppRoutes.studentProfile),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNoteCard extends StatelessWidget {
  const _PrivacyNoteCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.card),
            child: Icon(Icons.shield_outlined, size: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Your submitted document is private and available only to '
              'you and authorized platform reviewers.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryColumn extends StatelessWidget {
  const _SecondaryColumn();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentEducationVerificationProvider>();
    final verification = provider.verification;
    if (verification == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WhatHappensNextCard(verification: verification),
        const SizedBox(height: AppSpacing.md),
        const _ProfileConnectionCard(),
        const SizedBox(height: AppSpacing.md),
        const _PrivacyNoteCard(),
      ],
    );
  }
}

/// The submission form, reused for three real, backend-identical cases --
/// a brand-new submission, a rejected resubmission, and (Phase 8.1) a
/// pending-state document replacement -- all through the exact same
/// `POST /student/education-verification` endpoint
/// (`StudentEducationVerificationProvider.submit`). [prefillFrom] pre-fills
/// the fields from an existing verification (rejected resubmission and
/// replace both use the student's own already-loaded data); `null` means a
/// brand-new submission. [onCancel] is only ever provided for the
/// pending-replace case, where backing out is a real option -- the
/// not-submitted/rejected forms have no "cancel back to" state to return
/// to, so they never show a Cancel action.
class _SubmissionForm extends StatefulWidget {
  const _SubmissionForm({
    super.key,
    required this.pickFile,
    required this.title,
    required this.submitLabel,
    required this.successMessage,
    this.prefillFrom,
    this.onCancel,
    this.onSuccess,
  });

  final Future<PickedCvFile?> Function() pickFile;
  final String title;
  final String submitLabel;
  final String successMessage;
  final EducationVerificationModel? prefillFrom;
  final VoidCallback? onCancel;
  final VoidCallback? onSuccess;

  @override
  State<_SubmissionForm> createState() => _SubmissionFormState();
}

class _SubmissionFormState extends State<_SubmissionForm> {
  final _formKey = GlobalKey<FormState>();
  late final _institutionController = TextEditingController(
    text: widget.prefillFrom?.institutionName ?? '',
  );
  late final _degreeController = TextEditingController(
    text: widget.prefillFrom?.degreeOrProgram ?? '',
  );

  PickedCvFile? _selectedFile;
  String? _fileErrorMessage;

  // Matches the backend's own limits (StoreEducationVerificationRequest:
  // both text fields max:255, file max:5120 KB).
  static const _fieldMaxLength = 255;
  static const _maxFileSizeBytes = 5 * 1024 * 1024;

  @override
  void dispose() {
    _institutionController.dispose();
    _degreeController.dispose();
    super.dispose();
  }

  String? _validateRequired(String? value, String label) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '$label is required';
    if (trimmed.length > _fieldMaxLength) {
      return '$label must be $_fieldMaxLength characters or fewer';
    }
    return null;
  }

  Future<void> _pickFile() async {
    final picked = await widget.pickFile();
    if (picked == null) return;

    setState(() {
      if (!picked.filename.toLowerCase().endsWith('.pdf')) {
        _selectedFile = null;
        _fileErrorMessage = 'Only PDF files are supported.';
      } else if (picked.sizeInBytes > _maxFileSizeBytes) {
        _selectedFile = null;
        _fileErrorMessage = 'File must be 5 MB or smaller.';
      } else {
        _selectedFile = picked;
        _fileErrorMessage = null;
      }
    });
  }

  Future<void> _submit(StudentEducationVerificationProvider provider) async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    final file = _selectedFile;

    if (file == null) {
      setState(() => _fileErrorMessage ??= 'Please select a PDF file.');
    }
    if (!isValid || file == null) return;

    final success = await provider.submit(
      institutionName: _institutionController.text.trim(),
      degreeOrProgram: _degreeController.text.trim(),
      file: file,
    );
    if (!mounted || !success) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.successMessage)));
    widget.onSuccess?.call();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentEducationVerificationProvider>();
    final isLoading = provider.isSubmitting;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: widget.title, padding: EdgeInsets.zero),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: _institutionController,
              label: 'Institution',
              hint: 'e.g. State University',
              enabled: !isLoading,
              validator: (value) => _validateRequired(value, 'Institution'),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _degreeController,
              label: 'Degree / Program',
              hint: 'e.g. BSc Computer Science',
              enabled: !isLoading,
              textInputAction: TextInputAction.done,
              validator: (value) => _validateRequired(value, 'Degree / Program'),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AnimatedContainer(
              duration: AppMotion.reduced(context, AppMotion.fast),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: AppRadius.mediumRadius,
                border: Border.all(
                  color: _selectedFile != null ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SecondaryButton(
                    label: _selectedFile == null ? 'Select PDF' : 'Change PDF',
                    icon: Icons.attach_file,
                    onPressed: isLoading ? null : _pickFile,
                  ),
                  AnimatedSwitcher(
                    duration: AppMotion.reduced(context, AppMotion.fast),
                    child: _selectedFile != null
                        ? Padding(
                            key: const ValueKey('file-selected'),
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.picture_as_pdf_rounded,
                                  size: 18,
                                  color: AppColors.primaryDark,
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                                Expanded(
                                  child: Text(
                                    _selectedFile!.filename,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${(_selectedFile!.sizeInBytes / 1024).toStringAsFixed(0)} KB',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('no-file')),
                  ),
                ],
              ),
            ),
            if (_fileErrorMessage != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _fileErrorMessage!,
                style: textTheme.bodySmall?.copyWith(color: AppColors.error),
              ),
            ],
            if (provider.formErrorMessage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              AppErrorView(
                title: 'Something Went Wrong',
                message: provider.formErrorMessage!,
                compact: true,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (widget.onCancel != null)
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Cancel',
                      onPressed: isLoading ? null : widget.onCancel,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: PrimaryButton(
                      label: widget.submitLabel,
                      isLoading: isLoading,
                      onPressed: () => _submit(provider),
                    ),
                  ),
                ],
              )
            else
              PrimaryButton(
                label: widget.submitLabel,
                isLoading: isLoading,
                onPressed: () => _submit(provider),
              ),
          ],
        ),
      ),
    );
  }
}

/// A polished skeleton for the initial load — real card skeletons, never a
/// single giant spinner.
class _VerificationSkeleton extends StatelessWidget {
  const _VerificationSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: AppSpacing.lg),
          AppCardSkeleton(),
          SizedBox(height: AppSpacing.sm),
          AppCardSkeleton(),
          SizedBox(height: AppSpacing.sm),
          AppCardSkeleton(),
        ],
      ),
    );
  }
}
