import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Centralized, subtle shadow tokens.
///
/// Kept soft and shallow on purpose — this design system favors a flat,
/// professional look over heavy elevation.
class AppShadows {
  AppShadows._();

  static final List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.shadow.withValues(alpha: 0.08),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static final List<BoxShadow> elevated = [
    BoxShadow(
      color: AppColors.shadow.withValues(alpha: 0.12),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  static final List<BoxShadow> modal = [
    BoxShadow(
      color: AppColors.shadow.withValues(alpha: 0.18),
      blurRadius: 28,
      offset: const Offset(0, 10),
    ),
  ];
}
