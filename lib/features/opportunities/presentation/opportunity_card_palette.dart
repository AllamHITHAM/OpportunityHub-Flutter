import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A background/border pair for a pastel [OpportunityCard] variant.
///
/// Text always stays [AppColors.textPrimary]/[AppColors.textSecondary]
/// regardless of which tone is picked — every background here is chosen
/// (per theme) to keep that combination accessible, so tone never needs to
/// influence which text color renders.
class OpportunityCardTone {
  const OpportunityCardTone(this.background, this.border);

  final Color background;
  final Color border;
}

/// UI Phase 1.2/1.3's controlled pastel palette for opportunity cards — a
/// browsing accent, not a replacement brand palette. [AppColors.primary]
/// (#1A56DB), navy, and the AI purple remain the app's actual identity;
/// these six tones exist purely to make a dense grid of cards easier to
/// visually scan, the same way the reference marketplace's card grid does.
///
/// Deliberately NOT tied to any real status/category (opportunity type,
/// work mode, etc.) — see [opportunityCardTone], which assigns a tone
/// purely from the opportunity's ID, so no color here should ever be read
/// as meaning anything beyond "a different card than its neighbor".
///
/// UI Phase 1.3: dark mode gets its own deeply-muted tones (never a naive
/// "lower the opacity" inversion of the light pastels) — bright pastel
/// blocks would look wrong sitting on a deep navy background, so each dark
/// tone is a genuinely dark, desaturated variant of the same hue family.
const _lightOpportunityCardTones = [
  // Soft blue
  OpportunityCardTone(Color(0xFFEFF6FF), Color(0xFFBFDBFE)),
  // Soft violet/lavender — matches AppColorsLight.aiAccentBackground
  // exactly, keeping this one tone visually tied to the app's existing AI
  // accent.
  OpportunityCardTone(AppColorsLight.aiAccentBackground, Color(0xFFDDD6FE)),
  // Soft mint/cyan
  OpportunityCardTone(Color(0xFFECFEFF), Color(0xFFA5F3FC)),
  // Soft green
  OpportunityCardTone(Color(0xFFF0FDF4), Color(0xFFBBF7D0)),
  // Soft warm peach/rose
  OpportunityCardTone(Color(0xFFFFF1F2), Color(0xFFFBCFE8)),
  // Soft neutral/slate — reuses the app's own existing neutral surface, so
  // a plain/undecorated card still belongs to the same system.
  OpportunityCardTone(AppColorsLight.surfaceVariant, AppColorsLight.border),
];

const _darkOpportunityCardTones = [
  // Deep-tinted blue
  OpportunityCardTone(Color(0xFF16233B), Color(0xFF24344F)),
  // Deep-tinted violet/lavender — matches AppColorsDark.aiAccentBackground.
  OpportunityCardTone(AppColorsDark.aiAccentBackground, Color(0xFF3D2E5C)),
  // Deep-tinted mint/cyan
  OpportunityCardTone(Color(0xFF0F2630), Color(0xFF1E3B47)),
  // Deep-tinted green
  OpportunityCardTone(Color(0xFF16281E), Color(0xFF24402F)),
  // Deep-tinted warm peach/rose
  OpportunityCardTone(Color(0xFF2B1B22), Color(0xFF432934)),
  // Neutral/slate — reuses the app's own dark neutral surface.
  OpportunityCardTone(AppColorsDark.surfaceVariant, AppColorsDark.border),
];

/// Picks a stable tone for [opportunityId] — the same opportunity always
/// gets the same tone across rebuilds, refreshes, sessions, and theme
/// switches (a pure function of its real ID, never `Random`), and the
/// assignment carries no status/category meaning. Resolves against
/// [AppColors.isDark] freshly on every call, so a theme toggle picks up
/// the matching dark/light variant immediately.
OpportunityCardTone opportunityCardTone(int opportunityId) {
  final tones = AppColors.isDark ? _darkOpportunityCardTones : _lightOpportunityCardTones;
  final index = opportunityId % tones.length;
  return tones[index < 0 ? index + tones.length : index];
}
