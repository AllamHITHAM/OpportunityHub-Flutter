import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';

/// Parses [link] into a launchable `http`/`https` [Uri], or `null` if it's
/// malformed/legacy data that can't safely be opened — the caller falls
/// back to a plain, non-clickable tile instead of crashing or offering a
/// dead CTA. `Uri.tryParse` alone is too permissive (it happily parses
/// almost any string), so scheme and host are checked explicitly.
Uri? validHttpUri(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri;
}

/// Shown instead of [MeetingLinkCta] whenever an Online interview has no
/// safely-launchable meeting link — missing, empty, or malformed. Never
/// renders the raw field value (it may be garbage legacy data) and never
/// invents a URL; just a calm, honest placeholder message.
class MeetingLinkPlaceholder extends StatelessWidget {
  const MeetingLinkPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.videocam_outlined, size: 18, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Meeting link will appear here once provided.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A real, working "Open Meeting Link" action for Online interviews —
/// launches [uri] via `url_launcher` (first built as UI Phase 4.3 for the
/// Student Application Details screen; extracted here so the Organization
/// side can reuse the exact same real, working component rather than a
/// second copy that could drift). The raw link stays visible underneath as
/// small, selectable/copyable text — the CTA is the primary interaction,
/// never a naked URL, but the real value is never hidden either.
class MeetingLinkCta extends StatefulWidget {
  const MeetingLinkCta({super.key, required this.uri, required this.rawLink});

  final Uri uri;
  final String rawLink;

  @override
  State<MeetingLinkCta> createState() => _MeetingLinkCtaState();
}

class _MeetingLinkCtaState extends State<MeetingLinkCta> {
  bool _hovered = false;
  bool _launching = false;

  Future<void> _open() async {
    setState(() => _launching = true);
    var launched = false;
    try {
      launched = await launchUrl(
        widget.uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!mounted) return;
    setState(() => _launching = false);
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the meeting link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meeting Link',
          style: textTheme.labelSmall?.copyWith(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Semantics(
            button: true,
            label: 'Open Meeting Link',
            child: InkWell(
              onTap: _launching ? null : _open,
              borderRadius: AppRadius.mediumRadius,
              child: AnimatedContainer(
                duration: AppMotion.reduced(context, AppMotion.fast),
                curve: AppMotion.standard,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  borderRadius: AppRadius.mediumRadius,
                  boxShadow: _hovered ? AppShadows.card : const [],
                ),
                transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.videocam_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Expanded(
                      child: Text(
                        'Open Meeting Link',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_launching)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(
                        Icons.north_east_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        SelectableText(
          widget.rawLink,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
