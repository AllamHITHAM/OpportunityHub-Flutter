import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Derives up to two uppercase initials for an organization identity mark
/// (UI Phase 5.1) — deliberately a different algorithm from
/// `AppAvatar.initialsFor` (first+last word, one letter for a single word),
/// which exists for *people* and stays untouched so no unrelated person
/// avatar (Student Profile, admin/user avatars, ...) changes behavior.
///
/// Rules, in order:
/// - Blank/missing name → `''` (the caller shows a neutral building icon).
/// - A single word of one character → that character.
/// - A single word of two+ characters → its first two characters
///   ("ABOMOHAMAD" → "AB", "Globex" → "GL").
/// - Two or more words → the first letter of the first two words
///   ("ABC Technology" → "AT", "Acme Global Technologies" → "AG").
///
/// Never returns "null", "?", or anything malformed — a blank/whitespace
/// name always resolves to `''`.
String organizationInitials(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return '';

  final words = trimmed
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';

  if (words.length == 1) {
    final word = words.first;
    return (word.length == 1 ? word : word.substring(0, 2)).toUpperCase();
  }

  return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
}

/// A polished organization-identity fallback mark (UI Phase 5.1) — distinct
/// from the generic [AppAvatar] used for people, so changing this can never
/// affect a Student Profile avatar or any other person avatar elsewhere in
/// the app. Wired into Student Invitations this phase; written to be
/// reusable later for Applications, Opportunity Details, and other
/// organization-identity surfaces without further changes.
///
/// This is only ever a *fallback* — [logoUrl] exists purely so a real
/// organization-logo field can be wired in later without redesigning this
/// widget; no field like that exists in the API today, so every current
/// call site leaves it `null` and this always renders the initials mark.
/// Never fabricates a logo image.
class OrganizationAvatar extends StatelessWidget {
  const OrganizationAvatar({
    super.key,
    required this.name,
    this.logoUrl,
    this.size = 48,
    this.emphasized = false,
  });

  final String? name;
  final String? logoUrl;
  final double size;

  /// True while the caller wants a slightly stronger border/shadow — e.g.
  /// a Web hover state. Purely visual; this widget owns no hover state of
  /// its own so it stays a simple, easily-testable [StatelessWidget].
  final bool emphasized;

  bool get _hasLogo => logoUrl != null && logoUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final initials = organizationInitials(name);
    final hasName = name != null && name!.trim().isNotEmpty;
    final foreground = AppColors.isDark
        ? AppColors.primaryLight
        : AppColors.primaryDark;

    return Semantics(
      label: hasName ? '$name logo' : 'Organization',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryContainer,
              Color.lerp(AppColors.primaryContainer, AppColors.primary, 0.22)!,
            ],
          ),
          border: Border.all(
            color: emphasized
                ? AppColors.primary.withValues(alpha: 0.55)
                : AppColors.border,
            width: emphasized ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow.withValues(alpha: emphasized ? 0.12 : 0.06),
              blurRadius: emphasized ? 8 : 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Center(
              child: initials.isEmpty
                  ? Icon(
                      Icons.apartment_rounded,
                      size: size * 0.5,
                      color: foreground,
                    )
                  : Text(
                      initials,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: size * 0.38,
                        height: 1.0,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
            if (_hasLogo)
              Image.network(
                logoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}
