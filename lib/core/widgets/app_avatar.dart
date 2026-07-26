import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A user avatar: shows a network image when available, and otherwise
/// falls back to the user's initials (derived from [name]) or an icon.
///
/// Stateless by design — loading/error handling is delegated entirely to
/// [Image.network]'s own builders, so a malformed or unreachable URL can
/// never crash this widget; it just falls back to the initials/icon.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.imageUrl,
    this.name,
    this.size = 40,
    this.backgroundColor,
    this.foregroundColor,
    this.fallbackIcon = Icons.person_outline,
  });

  final String? imageUrl;
  final String? name;
  final double size;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconData fallbackIcon;

  /// Extracts up to two initials from [name], safely handling null, empty,
  /// and whitespace-only input.
  static String initialsFor(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return '';

    final parts = trimmed
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  bool get _hasImage => imageUrl != null && imageUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final initials = initialsFor(name);
    final bgColor = backgroundColor ?? AppColors.primaryContainer;
    final fgColor = foregroundColor ?? AppColors.primaryDark;
    final hasName = name != null && name!.trim().isNotEmpty;

    return Semantics(
      label: hasName ? '$name avatar' : 'User avatar',
      image: true,
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: ColoredBox(
            color: bgColor,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                _AvatarFallback(
                  initials: initials,
                  icon: fallbackIcon,
                  size: size,
                  color: fgColor,
                ),
                if (_hasImage)
                  Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const SizedBox.shrink();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({
    required this.initials,
    required this.icon,
    required this.size,
    required this.color,
  });

  final String initials;
  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (initials.isEmpty) {
      return Icon(icon, size: size * 0.55, color: color);
    }
    return Text(
      initials,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w600,
        fontSize: size * 0.4,
      ),
    );
  }
}
