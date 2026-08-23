import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';

/// A large, selectable account-type card for [AccountTypeSelectionScreen]
/// (UI Phase 1.5) — default / Web-hover / press / selected states, plus a
/// short list of real, existing capabilities for that role.
///
/// Tapping the card's icon/title/description/benefits area calls
/// [onSelect] only — it marks the card selected without navigating
/// anywhere, so selection reads as a deliberate, reversible choice rather
/// than an instant jump. Only the [actionLabel] button calls [onContinue],
/// which actually navigates. The button deliberately sits *outside* the
/// selectable area's `InkWell` (as a sibling, not a nested descendant) —
/// nesting two tappable regions the way `AppCard(onTap: ...)` would have
/// meant a tap on the button could also fire the outer `onSelect`, since
/// plain taps don't reject each other the way drag gestures do.
class InteractiveRoleCard extends StatefulWidget {
  const InteractiveRoleCard({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.description,
    required this.benefits,
    required this.actionLabel,
    required this.isSelected,
    required this.onSelect,
    required this.onContinue,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String description;
  final List<String> benefits;
  final String actionLabel;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onContinue;

  @override
  State<InteractiveRoleCard> createState() => _InteractiveRoleCardState();
}

class _InteractiveRoleCardState extends State<InteractiveRoleCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final normalDuration = AppMotion.reduced(context, AppMotion.normal);
    final fastDuration = AppMotion.reduced(context, AppMotion.fast);

    final lift = !widget.isSelected && _isHovered ? -3.0 : 0.0;
    final scale = _isPressed ? 0.985 : (!widget.isSelected && _isHovered ? 1.012 : 1.0);

    final borderColor = widget.isSelected
        ? widget.accentColor
        : (_isHovered
              ? widget.accentColor.withValues(alpha: 0.6)
              : AppColors.border);
    final backgroundColor = widget.isSelected
        ? Color.alphaBlend(
            widget.accentColor.withValues(alpha: 0.08),
            AppColors.card,
          )
        : AppColors.card;
    final shadow = widget.isSelected || _isHovered
        ? AppShadows.elevated
        : AppShadows.card;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: scale,
        duration: fastDuration,
        curve: AppMotion.standard,
        child: AnimatedContainer(
          duration: normalDuration,
          curve: AppMotion.standard,
          transform: Matrix4.translationValues(0, lift, 0),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: AppRadius.largeRadius,
            border: Border.all(
              color: borderColor,
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: shadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: AppColors.transparent,
                child: InkWell(
                  onTap: widget.onSelect,
                  onTapDown: (_) => _setPressed(true),
                  onTapUp: (_) => _setPressed(false),
                  onTapCancel: () => _setPressed(false),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.large),
                  ),
                  child: Semantics(
                    button: true,
                    selected: widget.isSelected,
                    label:
                        '${widget.title}. ${widget.description}'
                        '${widget.isSelected ? '. Selected' : ''}',
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              _RoleIconBadge(
                                icon: widget.icon,
                                accentColor: widget.accentColor,
                                isHovered: _isHovered || widget.isSelected,
                              ),
                              const Spacer(),
                              _SelectedCheck(
                                isSelected: widget.isSelected,
                                accentColor: widget.accentColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(widget.title, style: textTheme.titleLarge),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            widget.description,
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          for (final benefit in widget.benefits)
                            _BenefitRow(
                              text: benefit,
                              accentColor: widget.accentColor,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.cardPadding,
                  0,
                  AppSpacing.cardPadding,
                  AppSpacing.cardPadding,
                ),
                child: PrimaryButton(
                  label: widget.actionLabel,
                  onPressed: widget.onContinue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleIconBadge extends StatelessWidget {
  const _RoleIconBadge({
    required this.icon,
    required this.accentColor,
    required this.isHovered,
  });

  final IconData icon;
  final Color accentColor;
  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.reduced(context, AppMotion.normal),
      curve: AppMotion.standard,
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: AppRadius.mediumRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: isHovered ? 0.22 : 0.14),
            accentColor.withValues(alpha: isHovered ? 0.14 : 0.08),
          ],
        ),
      ),
      child: AnimatedScale(
        scale: isHovered ? 1.08 : 1.0,
        duration: AppMotion.reduced(context, AppMotion.normal),
        curve: AppMotion.standard,
        child: Icon(icon, size: 28, color: accentColor),
      ),
    );
  }
}

class _SelectedCheck extends StatelessWidget {
  const _SelectedCheck({required this.isSelected, required this.accentColor});

  final bool isSelected;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: AnimatedScale(
        scale: isSelected ? 1.0 : 0.0,
        duration: AppMotion.reduced(context, AppMotion.fast),
        curve: AppMotion.entrance,
        child: Container(
          decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(
            Icons.check_rounded,
            size: 16,
            color: AppColors.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.text, required this.accentColor});

  final String text;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: accentColor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
