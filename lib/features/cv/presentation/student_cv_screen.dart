import 'package:file_picker/file_picker.dart';
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
import '../../../models/cv_model.dart';
import '../../../models/cv_skill_suggestion_model.dart';
import '../../../providers/student_cv_provider.dart';
import '../../../routes/app_routes.dart';
import '../data/picked_cv_file.dart';

const _tabletBreakpoint = 600.0;
const _desktopBreakpoint = 1200.0;

enum _ScreenTier { mobile, tablet, desktop }

_ScreenTier _tierFor(double width) {
  if (width >= _desktopBreakpoint) return _ScreenTier.desktop;
  if (width >= _tabletBreakpoint) return _ScreenTier.tablet;
  return _ScreenTier.mobile;
}

/// UI Phase 6.2: the exact real backend messages for the two document-
/// validation business errors (`Student\CVController::extractSkills()`,
/// read-only backend) — matched verbatim, the same convention every other
/// business error in this app already uses (e.g. the CV-delete 409). Any
/// other error message (a genuine provider/network failure) falls through
/// to the generic AI error panel instead.
const _notACvMessage =
    "This document doesn't appear to be a CV or resume. Upload a CV to use AI Skill Analysis.";
const _insufficientTextMessage =
    "We couldn't find enough readable text in this PDF to analyze it.";

/// Opens the platform file picker restricted to a single PDF and returns
/// the picked bytes, or `null` if the user cancelled or the platform
/// couldn't provide bytes. The real, default implementation of
/// [StudentCvScreen.pickCvFile] — overridable in tests so the Add CV flow
/// can be exercised without a real platform file-picker channel.
Future<PickedCvFile?> pickCvFileFromDevice() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final picked = result.files.single;
  final bytes = picked.bytes;
  if (bytes == null) return null;

  return PickedCvFile(filename: picked.name, bytes: bytes);
}

/// Premium CV management + AI Skill Analysis (UI Phase 6) — a real,
/// already-implemented feature set given a design worthy of it:
///
/// - **CV management** is real multipart PDF upload (`file_picker` +
///   `POST /student/cvs` as `multipart/form-data`, Phase 8A-4) — never a
///   fake drag-and-drop, since a real upload already exists. Default/
///   Delete/View all call the exact same [StudentCvProvider] actions as
///   before; only presentation changed.
/// - **AI Skill Analysis** (`POST /student/cvs/{cv}/extract-skills`,
///   Phase 8A-6/8A-6.1) is a single, transient request — nothing is
///   persisted by the call itself except idempotent `CvSkillEvidence`/
///   `SkillSuggestion` bookkeeping server-side (see
///   `AiSkillExtractionService`'s own doc comment on the read-only
///   backend). It never auto-adds a skill; "Add Selected Skills" is the
///   one explicit, separate action that does, via the existing Student
///   Skill endpoint. Confidence (0.0–1.0) is real and returned by the
///   backend; there is no "evidence excerpt/quote" field to show, and no
///   CV-level "has this been analyzed" flag exists (`parsed_text` is
///   `hidden` on the backend `CV` model) — so this screen never claims a
///   CV is or isn't "AI-ready", and never shows a progress percentage,
///   since the backend never reports one (it's a single bounded HTTP
///   call, not a multi-step job).
class StudentCvScreen extends StatefulWidget {
  const StudentCvScreen({super.key, this.pickCvFile = pickCvFileFromDevice});

  /// Defaults to the real platform file picker ([pickCvFileFromDevice]) —
  /// overridable so widget tests can simulate a file selection without a
  /// real platform channel.
  final Future<PickedCvFile?> Function() pickCvFile;

  @override
  State<StudentCvScreen> createState() => _StudentCvScreenState();
}

class _StudentCvScreenState extends State<StudentCvScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentCvProvider>().loadCvs();
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

  Future<void> _openAddCvSheet() async {
    final provider = context.read<StudentCvProvider>();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: _AddCvSheet(pickFile: widget.pickCvFile),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('CV added successfully')));
    }
  }

  Future<void> _confirmDelete(CvModel cv) async {
    final provider = context.read<StudentCvProvider>();

    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete CV',
      message:
          'Are you sure you want to delete "${cv.title}"? '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      type: AppConfirmationType.danger,
    );
    if (!confirmed) return;

    final success = await provider.deleteCv(cv.id);
    if (!mounted) return;

    if (!success && provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _setDefault(CvModel cv) async {
    final provider = context.read<StudentCvProvider>();

    final success = await provider.setDefaultCv(cv.id);
    if (!mounted) return;

    if (!success && provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  /// Opens the Rename dialog and, on real backend-confirmed success, shows
  /// a brief confirmation. UI Phase 6.2: metadata only — the PDF is never
  /// touched, and this never runs AI extraction.
  Future<void> _renameCv(CvModel cv) async {
    final provider = context.read<StudentCvProvider>();
    final renamed = await showDialog<bool>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: _RenameCvDialog(cv: cv),
      ),
    );
    if (renamed == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('CV renamed successfully')));
    }
  }

  /// Opens the CV in a new browser tab on Web (a real, honest limitation
  /// is reported on other platforms — see `cv_file_opener_io.dart`). UI
  /// Phase 6.3: previously this only ever fetched bytes into memory and
  /// claimed "downloaded" regardless of whether anything actually
  /// appeared — real success now means the viewer was actually triggered.
  Future<void> _viewCv(CvModel cv) async {
    final provider = context.read<StudentCvProvider>();

    final success = await provider.viewCv(cv.id, cv.title);
    if (!mounted) return;

    if (!success && provider.viewErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.viewErrorMessage!)));
    }
  }

  /// Triggers a real browser download on Web (appears in Chrome
  /// Downloads/Ctrl+J) — a distinct action from [_viewCv], never the same
  /// code path.
  Future<void> _downloadCv(CvModel cv) async {
    final provider = context.read<StudentCvProvider>();

    final success = await provider.downloadCvFile(cv.id, cv.title);
    if (!mounted) return;

    if (!success && provider.downloadErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.downloadErrorMessage!)));
    }
  }

  /// Runs AI skill extraction for [cv]. UI Phase 6: the result now lives
  /// inline on the card itself (an [AnimatedSwitcher] over idle/
  /// analyzing/result/error), not a separate modal sheet — the exact same
  /// [StudentCvProvider] state as before, just presented as part of the
  /// main page flow instead of a popup.
  Future<void> _analyzeCv(CvModel cv) => context.read<StudentCvProvider>().extractSkills(cv.id);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentCvProvider>();
    final tier = _tierFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My CVs'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            onPressed: () => context.push(AppRoutes.studentSkills),
            icon: const Icon(Icons.psychology_outlined),
            tooltip: 'My Skills',
          ),
          IconButton(
            onPressed: _openAddCvSheet,
            icon: const Icon(Icons.add),
            tooltip: 'Add CV',
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(provider, tier)),
    );
  }

  Widget _buildBody(StudentCvProvider provider, _ScreenTier tier) {
    if (provider.isLoadingList && provider.cvs.isEmpty) {
      return _CvLibrarySkeleton(tier: tier);
    }

    if (provider.listErrorMessage != null && provider.cvs.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: () => provider.loadCvs(forceRefresh: true),
      );
    }

    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;
    final maxWidth = tier == _ScreenTier.desktop ? 1100.0 : 760.0;

    if (provider.cvs.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => provider.loadCvs(forceRefresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PageHeader(tier: tier, entranceController: _entranceController),
              SizedBox(
                height: 440,
                child: AppEmptyView(
                  icon: Icons.description_outlined,
                  title: 'Build Your Opportunity Profile',
                  message:
                      'Add your first CV to start applying and discover '
                      'skills with AI.',
                  actionLabel: 'Add CV',
                  onAction: _openAddCvSheet,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cvs = provider.cvs;

    return RefreshIndicator(
      onRefresh: () => provider.loadCvs(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PageHeader(tier: tier, entranceController: _entranceController),
                _Stagger(
                  controller: _entranceController,
                  index: 1,
                  count: 4,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.lg,
                      horizontalPadding,
                      0,
                    ),
                    child: _SummaryAndHighlightRow(tier: tier, cvs: cvs),
                  ),
                ),
                _Stagger(
                  controller: _entranceController,
                  index: 2,
                  count: 4,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.lg,
                      horizontalPadding,
                      0,
                    ),
                    child: SectionHeader(
                      title: 'CV Library',
                      subtitle: cvs.length == 1
                          ? '1 resume on file'
                          : '${cvs.length} resumes on file',
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.xs,
                    horizontalPadding,
                    AppSpacing.xxl,
                  ),
                  child: AnimatedSize(
                    duration: AppMotion.reduced(context, AppMotion.normal),
                    curve: AppMotion.standard,
                    alignment: Alignment.topCenter,
                    child: _CvLibraryGrid(
                      tier: tier,
                      cvs: cvs,
                      entranceController: _entranceController,
                      onRename: _renameCv,
                      onSetDefault: _setDefault,
                      onDelete: _confirmDelete,
                      onView: _viewCv,
                      onDownload: _downloadCv,
                      onAnalyze: _analyzeCv,
                      onAddAnotherCv: _openAddCvSheet,
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
/// this session already define (see e.g. `StudentApplicationsScreen`'s own
/// doc comment on why it's kept separate rather than shared).
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

/// A compact page identity — not a giant hero. A small icon badge uses the
/// app's own established AI-accent gradient (`[primary, aiAccent]`,
/// already used by `StudentHomeScreen`'s discovery visual) since this page
/// is genuinely about both ordinary CV management and real AI analysis.
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
          count: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.aiAccent],
                  ),
                  boxShadow: AppShadows.card,
                ),
                child: const Icon(
                  Icons.description_rounded,
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
                      'My CVs',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage your resumes and use AI to uncover skills '
                      'from your experience.',
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

/// [CV Summary] + [AI capability highlight], side by side at tablet/desktop
/// widths, stacked on mobile — matching this phase's own preferred wide-Web
/// concept. Neither panel invents data: the summary uses only real, already
/// -loaded [CvModel] fields, and the highlight panel is purely explanatory
/// (no per-CV action lives here — Analyze stays on each CV's own card,
/// since analysis is inherently per-CV, not global; see this phase's own
/// note on avoiding an invented "selected CV" state).
class _SummaryAndHighlightRow extends StatelessWidget {
  const _SummaryAndHighlightRow({required this.tier, required this.cvs});

  final _ScreenTier tier;
  final List<CvModel> cvs;

  @override
  Widget build(BuildContext context) {
    final summary = _CvSummaryCard(cvs: cvs);
    final highlight = const _AiHighlightCard();

    if (tier == _ScreenTier.mobile) {
      return Column(
        children: [
          summary,
          const SizedBox(height: AppSpacing.sm),
          highlight,
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: summary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(flex: 3, child: highlight),
        ],
      ),
    );
  }
}

/// Real, truthful counts only — [CvModel.isDefault]/[CvModel.createdByAi]
/// are the only per-CV flags this screen's data actually carries; there is
/// no "AI-analyzed CVs" count anywhere (analysis is a transient request,
/// never persisted as a CV-level flag — see this file's own top doc
/// comment), so it is never shown here.
class _CvSummaryCard extends StatelessWidget {
  const _CvSummaryCard({required this.cvs});

  final List<CvModel> cvs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    CvModel? defaultCv;
    for (final cv in cvs) {
      if (cv.isDefault) {
        defaultCv = cv;
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.largeRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'CV Summary',
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Total CVs',
                style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: cvs.length),
                duration: AppMotion.reduced(context, const Duration(milliseconds: 700)),
                curve: AppMotion.entrance,
                builder: (context, value, _) => Text(
                  '$value',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.star_outline_rounded, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Default',
                style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              Flexible(
                child: AnimatedSwitcher(
                  duration: AppMotion.reduced(context, AppMotion.normal),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Text(
                    defaultCv?.title ?? 'Not set',
                    key: ValueKey(defaultCv?.id),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: defaultCv == null
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Purely explanatory — describes the real, already-implemented AI Skill
/// Analysis workflow (analyze → review → add), never a per-CV action.
/// Restrained: the AI accent (`aiAccent`) appears only here and on each
/// card's own AI section, never on ordinary CV controls.
class _AiHighlightCard extends StatelessWidget {
  const _AiHighlightCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.aiAccentBackground,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: AppColors.aiAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.aiAccent],
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'AI Skill Analysis',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.aiAccentDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Analyze any CV below to discover skills AI finds in your '
            'experience — you choose which ones to add to your profile.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: const [
              _AiStep(icon: Icons.picture_as_pdf_outlined, label: 'Upload'),
              _AiStep(icon: Icons.auto_awesome, label: 'Analyze'),
              _AiStep(icon: Icons.check_circle_outline_rounded, label: 'Review & Add'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiStep extends StatelessWidget {
  const _AiStep({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.aiAccentDark),
        const SizedBox(width: 4),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: AppColors.aiAccentDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Lays CV cards out as a single column on mobile/tablet, or a real
/// two-column grid at the desktop tier — a plain `Wrap` of fixed-width
/// children (not `GridView`), since cards have genuinely variable height
/// (an open AI results panel makes one card taller than its neighbors).
class _CvLibraryGrid extends StatelessWidget {
  const _CvLibraryGrid({
    required this.tier,
    required this.cvs,
    required this.entranceController,
    required this.onRename,
    required this.onSetDefault,
    required this.onDelete,
    required this.onView,
    required this.onDownload,
    required this.onAnalyze,
    required this.onAddAnotherCv,
  });

  final _ScreenTier tier;
  final List<CvModel> cvs;
  final AnimationController entranceController;
  final ValueChanged<CvModel> onRename;
  final ValueChanged<CvModel> onSetDefault;
  final ValueChanged<CvModel> onDelete;
  final ValueChanged<CvModel> onView;
  final ValueChanged<CvModel> onDownload;
  final ValueChanged<CvModel> onAnalyze;
  final VoidCallback onAddAnotherCv;

  @override
  Widget build(BuildContext context) {
    if (tier != _ScreenTier.desktop) {
      return Column(
        key: const ValueKey('cv-grid-mobile'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cvs.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _Stagger(
              controller: entranceController,
              index: 3,
              count: 4,
              child: _CvCard(
                cv: cvs[i],
                onRename: () => onRename(cvs[i]),
                onSetDefault: () => onSetDefault(cvs[i]),
                onDelete: () => onDelete(cvs[i]),
                onView: () => onView(cvs[i]),
                onDownload: () => onDownload(cvs[i]),
                onAnalyze: () => onAnalyze(cvs[i]),
                onAddAnotherCv: onAddAnotherCv,
              ),
            ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      key: const ValueKey('cv-grid-desktop'),
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        final cardWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final cv in cvs)
              SizedBox(
                width: cardWidth,
                child: _Stagger(
                  controller: entranceController,
                  index: 3,
                  count: 4,
                  child: _CvCard(
                    cv: cv,
                    onRename: () => onRename(cv),
                    onSetDefault: () => onSetDefault(cv),
                    onDelete: () => onDelete(cv),
                    onView: () => onView(cv),
                    onDownload: () => onDownload(cv),
                    onAnalyze: () => onAnalyze(cv),
                    onAddAnotherCv: onAddAnotherCv,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A premium document card — real fields only. Reads [StudentCvProvider]
/// directly (mirrors the binding pattern other Phase-5/6 screens this
/// session already use) so the parent grid doesn't have to thread a dozen
/// per-CV flags through.
class _CvCard extends StatelessWidget {
  const _CvCard({
    required this.cv,
    required this.onRename,
    required this.onSetDefault,
    required this.onDelete,
    required this.onView,
    required this.onDownload,
    required this.onAnalyze,
    required this.onAddAnotherCv,
  });

  final CvModel cv;
  final VoidCallback onRename;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final VoidCallback onView;
  final VoidCallback onDownload;
  final VoidCallback onAnalyze;
  final VoidCallback onAddAnotherCv;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentCvProvider>();
    final isBusy = provider.isBusy(cv.id);
    final isViewing = provider.isViewingCv(cv.id);
    final isDownloading = provider.isDownloading(cv.id);

    final isThisCv = provider.extractingCvId == cv.id;
    final isAnalyzing = provider.isExtracting && isThisCv;
    final hasError = isThisCv && !provider.isExtracting && provider.extractionErrorMessage != null;
    final hasResult = isThisCv && !provider.isExtracting && provider.extractionErrorMessage == null;

    final Widget aiSection;
    if (isAnalyzing) {
      aiSection = const _AiProcessingPanel(key: ValueKey('ai-analyzing'));
    } else if (hasError) {
      final message = provider.extractionErrorMessage!;
      // UI Phase 6.2: the backend's document-validation gate (a real,
      // distinguishable business error, matched by its exact message —
      // this app's own established convention for every other business
      // error, e.g. the CV-delete 409) gets its own calmer, more specific
      // panel instead of the generic error state. A genuine
      // classification/extraction-provider failure never produces either
      // exact message, so it always falls through to the generic panel.
      if (message == _notACvMessage) {
        aiSection = _AiNotACvPanel(
          key: const ValueKey('ai-not-a-cv'),
          onAddAnotherCv: onAddAnotherCv,
        );
      } else if (message == _insufficientTextMessage) {
        aiSection = _AiInsufficientTextPanel(
          key: const ValueKey('ai-insufficient-text'),
          onAddAnotherCv: onAddAnotherCv,
        );
      } else {
        aiSection = _AiErrorPanel(
          key: const ValueKey('ai-error'),
          message: message,
          onRetry: onAnalyze,
        );
      }
    } else if (hasResult) {
      aiSection = _AiResultsPanel(
        key: ValueKey('ai-result-${cv.id}'),
        cv: cv,
        onAnalyzeAgain: onAnalyze,
      );
    } else {
      aiSection = _AiPromptRow(key: const ValueKey('ai-idle'), onAnalyze: onAnalyze);
    }

    return AnimatedContainer(
      duration: AppMotion.reduced(context, AppMotion.normal),
      curve: AppMotion.standard,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(
          color: cv.isDefault ? AppColors.primary : AppColors.border,
          width: cv.isDefault ? 1.5 : 1,
        ),
        boxShadow: cv.isDefault ? AppShadows.elevated : AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CvIdentityRow(cv: cv, onRename: onRename),
          const SizedBox(height: AppSpacing.xs),
          _CvMetaRow(cv: cv),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: AppSpacing.sm),
          _CvActionsRow(
            cv: cv,
            isBusy: isBusy,
            isViewing: isViewing,
            isDownloading: isDownloading,
            onSetDefault: onSetDefault,
            onDelete: onDelete,
            onView: onView,
            onDownload: onDownload,
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedSwitcher(
            duration: AppMotion.reduced(context, AppMotion.normal),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
            child: aiSection,
          ),
        ],
      ),
    );
  }
}

class _CvIdentityRow extends StatelessWidget {
  const _CvIdentityRow({required this.cv, required this.onRename});

  final CvModel cv;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryContainer,
          ),
          child: Icon(
            Icons.picture_as_pdf_rounded,
            color: AppColors.primaryDark,
            size: 22,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          // UI Phase 6.2: a subtle cross-fade whenever the real title
          // changes (i.e. right after a backend-confirmed rename) — keyed
          // by the title itself so only a genuine change animates.
          child: AnimatedSwitcher(
            duration: AppMotion.reduced(context, AppMotion.normal),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Text(
              cv.title,
              key: ValueKey(cv.title),
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            onPressed: onRename,
            icon: const Icon(Icons.edit_outlined),
            iconSize: 16,
            tooltip: 'Rename CV',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        AnimatedSwitcher(
          duration: AppMotion.reduced(context, AppMotion.normal),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: cv.isDefault
              ? const StatusChip(
                  key: ValueKey('default'),
                  icon: Icons.star_rounded,
                  label: 'Default',
                  type: AppStatusType.success,
                  compact: true,
                )
              : const SizedBox.shrink(key: ValueKey('not-default')),
        ),
      ],
    );
  }
}

class _CvMetaRow extends StatelessWidget {
  const _CvMetaRow({required this.cv});

  final CvModel cv;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      children: [
        const StatusChip(label: 'PDF', compact: true),
        StatusChip(label: 'Version ${cv.version}', compact: true),
        if (cv.createdAt != null)
          StatusChip(
            icon: Icons.event_outlined,
            label: 'Uploaded ${formatDate(cv.createdAt!)}',
            compact: true,
          ),
        if (cv.createdByAi)
          const StatusChip(
            label: 'AI Generated',
            type: AppStatusType.info,
            compact: true,
          ),
      ],
    );
  }
}

/// Real actions only — View CV and Set as Default (only when not already
/// default) as the two labeled actions, Download and Delete as compact
/// icon actions beside them (UI Phase 6.3 — View and Download are two
/// distinct real actions now, never the same code path). Responsive to
/// the card's own width, since desktop's 2-column grid gives each card
/// meaningfully less room than a single-column mobile layout would.
class _CvActionsRow extends StatelessWidget {
  const _CvActionsRow({
    required this.cv,
    required this.isBusy,
    required this.isViewing,
    required this.isDownloading,
    required this.onSetDefault,
    required this.onDelete,
    required this.onView,
    required this.onDownload,
  });

  final CvModel cv;
  final bool isBusy;
  final bool isViewing;
  final bool isDownloading;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final VoidCallback onView;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;

        final viewButton = SecondaryButton(
          label: 'View CV',
          icon: Icons.visibility_outlined,
          height: 40,
          isLoading: isViewing,
          onPressed: isViewing ? null : onView,
        );
        final downloadButton = _CvIconActionButton(
          icon: Icons.download_outlined,
          tooltip: 'Download CV',
          isBusy: isDownloading,
          onPressed: onDownload,
        );
        final deleteButton = _CvIconActionButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete CV',
          isBusy: isBusy,
          destructive: true,
          onPressed: onDelete,
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              viewButton,
              if (!cv.isDefault) ...[
                const SizedBox(height: AppSpacing.xs),
                SecondaryButton(
                  label: 'Set as Default',
                  icon: Icons.star_outline_rounded,
                  height: 40,
                  isLoading: isBusy,
                  onPressed: isBusy ? null : onSetDefault,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [downloadButton, const SizedBox(width: AppSpacing.xs), deleteButton],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: viewButton),
            if (!cv.isDefault) ...[
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: SecondaryButton(
                  label: 'Set as Default',
                  icon: Icons.star_outline_rounded,
                  height: 40,
                  isLoading: isBusy,
                  onPressed: isBusy ? null : onSetDefault,
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.xs),
            downloadButton,
            const SizedBox(width: AppSpacing.xs),
            deleteButton,
          ],
        );
      },
    );
  }
}

/// UI Phase 6.1/6.3: a small, bordered icon action (matching the height
/// and border language of the labeled `SecondaryButton`s beside it) plus
/// a Web hover state — Delete hovers error-red (destructive), Download
/// hovers the ordinary primary-blue tint (a normal, non-destructive
/// action), matching this design system's rule that purple/red-style
/// emphasis is reserved for what it genuinely means.
class _CvIconActionButton extends StatefulWidget {
  const _CvIconActionButton({
    required this.icon,
    required this.tooltip,
    required this.isBusy,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final bool isBusy;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  State<_CvIconActionButton> createState() => _CvIconActionButtonState();
}

class _CvIconActionButtonState extends State<_CvIconActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isBusy) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final hoverColor = widget.destructive ? AppColors.error : AppColors.primary;
    final hoverBackground = widget.destructive
        ? AppColors.errorBackground
        : AppColors.primaryContainer;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: Tooltip(
          message: widget.tooltip,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: AppRadius.mediumRadius,
            child: AnimatedContainer(
              duration: AppMotion.reduced(context, AppMotion.fast),
              curve: AppMotion.standard,
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: AppRadius.mediumRadius,
                border: Border.all(
                  color: _hovered ? hoverColor : AppColors.border,
                ),
                color: _hovered ? hoverBackground : AppColors.transparent,
              ),
              child: Icon(
                widget.icon,
                size: 20,
                color: _hovered ? hoverColor : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The idle state of a CV card's AI section — the real, hero "Analyze with
/// AI" entry point (UI Phase 6 §11).
class _AiPromptRow extends StatelessWidget {
  const _AiPromptRow({super.key, required this.onAnalyze});

  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.aiAccentBackground,
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: AppColors.aiAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.aiAccent],
                  ),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 15),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'AI Skill Analysis',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.aiAccentDark,
                      ),
                    ),
                    Text(
                      'Analyze this CV to identify skills from your experience.',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _AiGradientButton(label: 'Analyze with AI', onPressed: onAnalyze),
        ],
      ),
    );
  }
}

/// A one-shot, bounded processing surface — no fake progress percentage
/// (the backend is a single HTTP call, never a multi-step job), no
/// artificial delay, and no permanent loop: the pulse animation lives only
/// as long as this widget is mounted, i.e. only for the real duration of
/// the request.
class _AiProcessingPanel extends StatefulWidget {
  const _AiProcessingPanel({super.key});

  @override
  State<_AiProcessingPanel> createState() => _AiProcessingPanelState();
}

class _AiProcessingPanelState extends State<_AiProcessingPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (via AppMotion.isReduced) can only be read safely once
    // this element is fully mounted — never in initState. Guarded so the
    // real request's bounded duration only ever starts one repeat.
    if (_started) return;
    _started = true;
    if (!AppMotion.isReduced(context)) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.aiAccentBackground,
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: AppColors.aiAccent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.05).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.aiAccent],
                ),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 15),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Analyzing your CV…',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.aiAccentDark,
                  ),
                ),
                Text(
                  'Looking for skills and evidence in your experience.',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
    );
  }
}

/// A real, safe AI error state — the CV list/card is never affected, and
/// the specific backend message (e.g. "Text could not be extracted from
/// this CV.") is shown alongside a calm, safe headline. Retry re-runs the
/// exact same real action.
class _AiErrorPanel extends StatelessWidget {
  const _AiErrorPanel({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.errorBackground,
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: AppColors.error, size: 22),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "We couldn't analyze this CV right now.",
                      style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      message,
                      style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(label: 'Try Again', height: 40, onPressed: onRetry),
        ],
      ),
    );
  }
}

/// UI Phase 6.2: the backend classified this CV's text as not being
/// CV/resume-like content (`NOT_A_CV`). A calm, warning-toned (not
/// error-red) verdict — this is real backend enforcement working exactly
/// as intended, not a system failure. The CV itself is never deleted or
/// altered; no extracted skills are ever shown here. "Try Again" is
/// deliberately omitted — re-running analysis on this exact, unchanged
/// document would deterministically produce the same verdict again, so
/// the one useful real action is uploading a different, genuine CV.
class _AiNotACvPanel extends StatelessWidget {
  const _AiNotACvPanel({super.key, required this.onAddAnotherCv});

  final VoidCallback onAddAnotherCv;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningBackground,
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.description_outlined, color: AppColors.warning, size: 22),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to Analyze This Document',
                      style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _notACvMessage,
                      style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(label: 'Add Another CV', height: 40, onPressed: onAddAnotherCv),
        ],
      ),
    );
  }
}

/// UI Phase 6.2: the backend's own deterministic readable-text-length
/// check rejected this CV before any AI call (`INSUFFICIENT_TEXT`) —
/// distinct from [_AiNotACvPanel] (which means real text existed but
/// wasn't CV-like) and from [_AiErrorPanel] (a genuine provider failure).
/// Never claims OCR support this app doesn't have. "Try Again" is
/// deliberately omitted for the same reason as [_AiNotACvPanel] — the
/// already-extracted text never changes without a new upload.
class _AiInsufficientTextPanel extends StatelessWidget {
  const _AiInsufficientTextPanel({super.key, required this.onAddAnotherCv});

  final VoidCallback onAddAnotherCv;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningBackground,
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.text_snippet_outlined, color: AppColors.warning, size: 22),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "We couldn't find enough readable text in this PDF.",
                      style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Try a text-based PDF.',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(label: 'Add Another CV', height: 40, onPressed: onAddAnotherCv),
        ],
      ),
    );
  }
}

/// The real extraction result — real skills only, real confidence only, no
/// fabricated "Verified by AI" claim (a suggestion only becomes "CV
/// Evidence" once the backend's own `CvSkillEvidence` row genuinely exists
/// for it). Owns its own selection state so a fresh Analyze Again run (a
/// distinct [AnimatedSwitcher] child, since the AI section cycles through
/// `idle`/`analyzing` first) always starts with a clean, empty selection.
/// Only this many suggestions render immediately — beyond this, "View All"
/// reveals the rest (UI Phase 6.1). Keeps a many-skill result from making
/// a CV card extremely tall by default.
const _skillPreviewLimit = 5;

class _AiResultsPanel extends StatefulWidget {
  const _AiResultsPanel({super.key, required this.cv, required this.onAnalyzeAgain});

  final CvModel cv;
  final VoidCallback onAnalyzeAgain;

  @override
  State<_AiResultsPanel> createState() => _AiResultsPanelState();
}

class _AiResultsPanelState extends State<_AiResultsPanel> {
  final Set<int> _selectedSkillIds = {};

  /// UI Phase 6.1: presentation-only state — never triggers a real
  /// extraction request. Starts expanded (the panel auto-expands once
  /// right after a real successful analysis, since this whole widget is
  /// freshly created for each new result — see this file's own note on
  /// `_AiResultsPanel`'s key strategy in `_CvCard`).
  bool _collapsed = false;
  bool _showAllSkills = false;

  List<CvSkillSuggestion> _selectable(List<CvSkillSuggestion> suggestions) =>
      suggestions.where((s) => s.isAvailable && !s.alreadyAdded).toList();

  void _toggle(int skillId, bool selected) {
    setState(() {
      if (selected) {
        _selectedSkillIds.add(skillId);
      } else {
        _selectedSkillIds.remove(skillId);
      }
    });
  }

  void _toggleAll(List<CvSkillSuggestion> selectable) {
    setState(() {
      final allSelected = selectable.isNotEmpty &&
          selectable.every((s) => _selectedSkillIds.contains(s.skillId));
      if (allSelected) {
        for (final s in selectable) {
          _selectedSkillIds.remove(s.skillId);
        }
      } else {
        for (final s in selectable) {
          _selectedSkillIds.add(s.skillId!);
        }
      }
    });
  }

  Future<void> _addSelected(StudentCvProvider provider) async {
    final success = await provider.addSelectedSkills(_selectedSkillIds.toList());
    if (!mounted) return;

    if (success) {
      setState(_selectedSkillIds.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skills added successfully')),
      );
    } else if (provider.addSkillsErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.addSkillsErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentCvProvider>();
    final suggestions = provider.skillSuggestions;
    final total = suggestions.length;
    final addedCount = suggestions.where((s) => s.alreadyAdded).length;
    final pendingCount = total - addedCount;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.aiAccentBackground,
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: AppColors.aiAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResultsHeader(
            total: total,
            collapsed: _collapsed,
            onToggle: () => setState(() => _collapsed = !_collapsed),
          ),
          AnimatedSize(
            duration: AppMotion.reduced(context, AppMotion.normal),
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppMotion.reduced(context, AppMotion.normal),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _collapsed
                  ? _CollapsedSummary(
                      key: const ValueKey('collapsed'),
                      total: total,
                      added: addedCount,
                      pending: pendingCount,
                    )
                  : _buildExpandedBody(
                      context,
                      provider,
                      suggestions,
                      addedCount: addedCount,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedBody(
    BuildContext context,
    StudentCvProvider provider,
    List<CvSkillSuggestion> suggestions, {
    required int addedCount,
  }) {
    final textTheme = Theme.of(context).textTheme;

    if (suggestions.isEmpty) {
      return Column(
        key: const ValueKey('expanded-empty'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xs),
          Text(
            "We couldn't identify any clear skills from this CV's text.",
            style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Analyze Again',
                  height: 40,
                  onPressed: widget.onAnalyzeAgain,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: SecondaryButton(
                  label: 'View My Skills',
                  height: 40,
                  onPressed: () => context.push(AppRoutes.studentSkills),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final hasMore = suggestions.length > _skillPreviewLimit;
    final visible = _showAllSkills || !hasMore
        ? suggestions
        : suggestions.take(_skillPreviewLimit).toList();

    return Column(
      key: const ValueKey('expanded-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xs),
        if (_selectable(suggestions).isNotEmpty)
          _SelectAllRow(
            allSelected: _selectable(suggestions).every(
              (s) => _selectedSkillIds.contains(s.skillId),
            ),
            onChanged: () => _toggleAll(_selectable(suggestions)),
          ),
        AnimatedSize(
          duration: AppMotion.reduced(context, AppMotion.normal),
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final suggestion in visible) ...[
                const SizedBox(height: AppSpacing.xxs),
                _SkillSuggestionCard(
                  suggestion: suggestion,
                  selected: _selectedSkillIds.contains(suggestion.skillId),
                  onChanged: _toggle,
                ),
              ],
            ],
          ),
        ),
        if (hasMore) ...[
          const SizedBox(height: AppSpacing.xxs),
          _ViewAllToggle(
            total: suggestions.length,
            expanded: _showAllSkills,
            onTap: () => setState(() => _showAllSkills = !_showAllSkills),
          ),
        ],
        if (provider.addSkillsErrorMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            provider.addSkillsErrorMessage!,
            style: textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 420;
            final analyzeAgain = SecondaryButton(
              label: 'Analyze Again',
              height: 40,
              onPressed: widget.onAnalyzeAgain,
            );
            final viewSkills = SecondaryButton(
              label: 'View My Skills',
              height: 40,
              onPressed: () => context.push(AppRoutes.studentSkills),
            );
            final addButton = PrimaryButton(
              label: _selectedSkillIds.isEmpty
                  ? 'Add Selected Skills'
                  : 'Add ${_selectedSkillIds.length} Skill${_selectedSkillIds.length == 1 ? '' : 's'}',
              height: 40,
              isLoading: provider.isAddingSkills,
              onPressed: _selectedSkillIds.isEmpty || provider.isAddingSkills
                  ? null
                  : () => _addSelected(provider),
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  addButton,
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(child: analyzeAgain),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: viewSkills),
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: analyzeAgain),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: viewSkills),
                const SizedBox(width: AppSpacing.xs),
                Expanded(flex: 2, child: addButton),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Always visible regardless of collapsed state — real title, real count,
/// and the one control that toggles collapse/expand (UI Phase 6.1).
class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.total,
    required this.collapsed,
    required this.onToggle,
  });

  final int total;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: collapsed ? 'Expand AI analysis results' : 'Collapse AI analysis results',
      child: InkWell(
        onTap: onToggle,
        borderRadius: AppRadius.smallRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.aiAccentDark),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'AI Analysis Results',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.aiAccentDark,
                      ),
                    ),
                    Text(
                      total == 0
                          ? 'No skills found'
                          : '$total skill${total == 1 ? '' : 's'} found',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: collapsed ? 0 : 0.5,
                duration: AppMotion.reduced(context, AppMotion.fast),
                curve: AppMotion.standard,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.aiAccentDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The collapsed state's compact summary — real, locally-derived counts
/// only ([total]/[added]/[pending] all come straight from the already-
/// loaded suggestion list).
class _CollapsedSummary extends StatelessWidget {
  const _CollapsedSummary({
    super.key,
    required this.total,
    required this.added,
    required this.pending,
  });

  final int total;
  final int added;
  final int pending;

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xxs,
        children: [
          _CountPill(value: total, label: total == 1 ? 'skill discovered' : 'skills discovered'),
          if (added > 0) _CountPill(value: added, label: 'already added'),
          if (pending > 0) _CountPill(value: pending, label: 'pending'),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Text(
        '$value $label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Reveals/hides the skills beyond [_skillPreviewLimit] — real count only,
/// never re-triggers extraction (UI Phase 6.1).
class _ViewAllToggle extends StatelessWidget {
  const _ViewAllToggle({required this.total, required this.expanded, required this.onTap});

  final int total;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: expanded ? 'Show fewer skills' : 'View all $total skills',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smallRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                expanded ? 'Show Less' : 'View All $total Skills',
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.aiAccentDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: AppMotion.reduced(context, AppMotion.fast),
                curve: AppMotion.standard,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.aiAccentDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({required this.allSelected, required this.onChanged});

  final bool allSelected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onChanged,
      borderRadius: AppRadius.smallRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(value: allSelected, onChanged: (_) => onChanged()),
            Flexible(
              child: Text(
                'Select all available',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One AI-suggested skill — real name and real confidence only.
/// "CV Evidence" is shown only once the backend's own idempotent
/// `CvSkillEvidence` bookkeeping genuinely makes this claim addable
/// ([CvSkillSuggestion.isAvailable]); never "Verified by AI".
class _SkillSuggestionCard extends StatelessWidget {
  const _SkillSuggestionCard({
    required this.suggestion,
    required this.selected,
    required this.onChanged,
  });

  final CvSkillSuggestion suggestion;
  final bool selected;
  final void Function(int skillId, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canSelect = suggestion.isAvailable && !suggestion.alreadyAdded;
    final percent = (suggestion.confidence * 100).round();

    final String stateLabel;
    final AppStatusType stateType;
    if (suggestion.alreadyAdded) {
      stateLabel = 'Already Added';
      stateType = AppStatusType.success;
    } else if (!suggestion.isAvailable) {
      stateLabel = 'Pending Catalog Approval';
      stateType = AppStatusType.warning;
    } else {
      stateLabel = 'CV Evidence';
      stateType = AppStatusType.info;
    }

    return Semantics(
      label: '${suggestion.name}, $percent% confidence, $stateLabel',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.smallRadius,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: canSelect
                  ? Checkbox(
                      value: selected,
                      onChanged: (value) => onChanged(suggestion.skillId!, value ?? false),
                    )
                  : Icon(
                      suggestion.alreadyAdded
                          ? Icons.check_circle_rounded
                          : Icons.hourglass_top_rounded,
                      size: 18,
                      color: suggestion.alreadyAdded
                          ? AppColors.success
                          : AppColors.textMuted,
                    ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 12, color: AppColors.aiAccent),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          suggestion.name,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: ClipRRect(
                          borderRadius: AppRadius.smallRadius,
                          child: LinearProgressIndicator(
                            value: suggestion.confidence,
                            minHeight: 4,
                            backgroundColor: AppColors.surfaceVariant,
                            color: AppColors.aiAccent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '$percent% confidence',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // A dedicated row (not squeezed beside the confidence
                  // meter) — "Pending Catalog Approval" is long enough
                  // that sharing a row with the meter overflowed at
                  // realistic card widths (UI Phase 6 QA).
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(compact: true, label: stateLabel, type: stateType),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Analyze with AI" hero CTA — reuses this app's own established AI
/// gradient (`[primary, aiAccent]`, the same pattern
/// `_MeetingLinkCta`/`StudentHomeScreen`'s discovery visual already use)
/// rather than inventing a new AI visual language.
class _AiGradientButton extends StatefulWidget {
  const _AiGradientButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_AiGradientButton> createState() => _AiGradientButtonState();
}

class _AiGradientButtonState extends State<_AiGradientButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        label: widget.label,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: AppRadius.mediumRadius,
          child: AnimatedContainer(
            duration: AppMotion.reduced(context, AppMotion.fast),
            curve: AppMotion.standard,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.aiAccent],
              ),
              borderRadius: AppRadius.mediumRadius,
              boxShadow: _hovered ? AppShadows.card : const [],
            ),
            transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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

/// A small, responsive dialog to rename a CV (UI Phase 6.2) — metadata
/// only, the PDF file is never touched, and this never runs AI
/// extraction. Prefilled with the real current title; duplicate submits
/// are blocked by [StudentCvProvider.renameCv] sharing the same busy-id
/// guard delete/set-default already use.
class _RenameCvDialog extends StatefulWidget {
  const _RenameCvDialog({required this.cv});

  final CvModel cv;

  @override
  State<_RenameCvDialog> createState() => _RenameCvDialogState();
}

class _RenameCvDialogState extends State<_RenameCvDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(text: widget.cv.title);

  static const _titleMaxLength = 255;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String? _validateTitle(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Title is required';
    if (trimmed.length > _titleMaxLength) {
      return 'Title must be $_titleMaxLength characters or fewer';
    }
    return null;
  }

  Future<void> _submit(StudentCvProvider provider) async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final success = await provider.renameCv(widget.cv.id, _titleController.text.trim());
    if (!mounted || !success) return;

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentCvProvider>();
    final isLoading = provider.isBusy(widget.cv.id);
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Rename CV',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _titleController,
                  label: 'Title',
                  enabled: !isLoading,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  validator: _validateTitle,
                  onFieldSubmitted: (_) => _submit(provider),
                ),
                if (provider.renameErrorMessage != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    provider.renameErrorMessage!,
                    style: textTheme.bodySmall?.copyWith(color: AppColors.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Cancel',
                        onPressed: isLoading
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Save Name',
                        isLoading: isLoading,
                        onPressed: () => _submit(provider),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A modal bottom sheet to add a CV: a title field plus a real PDF file
/// picker — the same real multipart-upload flow as before, polished.
class _AddCvSheet extends StatefulWidget {
  const _AddCvSheet({required this.pickFile});

  final Future<PickedCvFile?> Function() pickFile;

  @override
  State<_AddCvSheet> createState() => _AddCvSheetState();
}

class _AddCvSheetState extends State<_AddCvSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();

  PickedCvFile? _selectedFile;
  String? _fileErrorMessage;
  bool _justAdded = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  // Matches the backend's own limits (StoreCVRequest: title max:255,
  // file max:5120 KB) so an over-length/oversized value is rejected
  // locally instead of round-tripping to a 422.
  static const _titleMaxLength = 255;
  static const _maxFileSizeBytes = 5 * 1024 * 1024;

  String? _validateTitle(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Title is required';
    }
    if (trimmed.length > _titleMaxLength) {
      return 'Title must be $_titleMaxLength characters or fewer';
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

  Future<void> _submit(StudentCvProvider provider) async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    final file = _selectedFile;

    if (file == null) {
      setState(() => _fileErrorMessage ??= 'Please select a PDF file.');
    }
    if (!isValid || file == null) return;

    final created = await provider.createCv(
      title: _titleController.text.trim(),
      file: file,
    );
    if (!mounted) return;
    if (created == null) return;

    setState(() => _justAdded = true);
    await Future.delayed(AppMotion.reduced(context, const Duration(milliseconds: 500)));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentCvProvider>();
    final isLoading = provider.isSubmitting;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: AnimatedSwitcher(
          duration: AppMotion.reduced(context, AppMotion.normal),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _justAdded
              ? const Padding(
                  key: ValueKey('add-cv-success'),
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: AppSuccessView(
                    compact: true,
                    title: 'CV Added',
                    message: 'Your resume is ready to use.',
                  ),
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryContainer,
                            ),
                            child: Icon(
                              Icons.upload_file_rounded,
                              color: AppColors.primaryDark,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          const Expanded(child: SectionHeader(title: 'Add CV', padding: EdgeInsets.zero)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        controller: _titleController,
                        label: 'Title',
                        hint: 'e.g. Software Engineer CV',
                        enabled: !isLoading,
                        textInputAction: TextInputAction.done,
                        validator: _validateTitle,
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
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
                                child: Container(
                                  padding: const EdgeInsets.all(AppSpacing.xs),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    borderRadius: AppRadius.smallRadius,
                                  ),
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
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('no-file')),
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
                      PrimaryButton(
                        label: 'Add CV',
                        isLoading: isLoading,
                        onPressed: () => _submit(provider),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _CvLibrarySkeleton extends StatelessWidget {
  const _CvLibrarySkeleton({required this.tier});

  final _ScreenTier tier;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 84, color: AppColors.primaryContainer.withValues(alpha: 0.4)),
          Padding(
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSkeleton(height: 90, borderRadius: AppRadius.largeRadius),
                const SizedBox(height: AppSpacing.lg),
                const _CvCardSkeleton(),
                const SizedBox(height: AppSpacing.sm),
                const _CvCardSkeleton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A higher-fidelity skeleton shaped like the real card above.
class _CvCardSkeleton extends StatelessWidget {
  const _CvCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppSkeleton(width: 44, height: 44, borderRadius: AppRadius.pillRadius),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    AppSkeleton(height: 16, width: 160),
                    SizedBox(height: 6),
                    AppSkeleton(height: 12, width: 100),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const AppSkeleton(height: 40, borderRadius: AppRadius.mediumRadius),
          const SizedBox(height: AppSpacing.sm),
          const AppSkeleton(height: 64, borderRadius: AppRadius.mediumRadius),
        ],
      ),
    );
  }
}
