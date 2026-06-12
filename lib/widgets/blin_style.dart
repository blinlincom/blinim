import 'package:flutter/material.dart';

/// Blinlin 2026 minimal visual system.
///
/// This file is UI-only. It keeps the old public class names so existing IM,
/// WebRTC and WuKongIM code can keep working while the visual layer changes.
class BlinStyle {
  static const primary = Color(0xFF6366F1);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);

  static const bg = Color(0xFFF8FAFC);
  static const bgElevated = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const subtle = Color(0xFF94A3B8);
  static const line = Color(0xFFE2E8F0);
  static const softFill = Color(0xFFF1F5F9);
  static const danger = Color(0xFFEF4444);

  static const darkBg = Color(0xFF0F172A);
  static const darkSurface = Color(0xFF1E293B);
  static const darkLine = Color(0xFF334155);

  // Compatibility aliases used by older widgets.
  static const green = success;
  static const cyan = primary;
  static const blue = primary;
  static const purple = primary;
  static const pink = Color(0xFFEC4899);
  static const orange = warning;
  static const softInk = ink;

  static const double pagePadding = 20;
  static const double moduleGap = 24;
  static const double verticalGap = 24;
  static const double compactGap = 12;
  static const double cardPadding = 16;
  static const double cardRadius = 20;
  static const double buttonRadius = 16;
  static const double iconSize = 24;

  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x0F000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  static BoxShadow softShadow([double opacity = .06]) => cardShadow;

  static BoxShadow glowShadow(Color color, [double opacity = .10]) =>
      cardShadow;

  static BorderSide hairline(BuildContext context, [double opacity = 1]) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BorderSide(
      color: (dark ? darkLine : line).withValues(alpha: opacity),
    );
  }

  static Color surface(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? darkSurface : bgElevated;
  }

  static Color page(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? darkBg : bg;
  }
}

class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double radius;
  final VoidCallback? onTap;
  final bool loud;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color,
    this.radius = BlinStyle.cardRadius,
    this.onTap,
    this.loud = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final box = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? BlinStyle.surface(context),
        borderRadius: borderRadius,
        border: Border.all(color: BlinStyle.hairline(context).color),
        boxShadow: const [BlinStyle.cardShadow],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: borderRadius, onTap: onTap, child: box),
    );
  }
}

class GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  const GradientIcon({
    super.key,
    required this.icon,
    this.size = 46,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Theme.of(context).colorScheme.primary, BlinStyle.success],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(
      icon,
      color: Theme.of(context).colorScheme.onPrimary,
      size: iconSize,
    ),
  );
}

class PageBackdrop extends StatelessWidget {
  final Widget child;
  const PageBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: BlinStyle.page(context)),
      child: child,
    );
  }
}

class AppTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(
      BlinStyle.pagePadding,
      12,
      BlinStyle.pagePadding,
      12,
    ),
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Container(
      color: BlinStyle.page(context),
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Wrap(spacing: 8, children: actions),
          ],
        ],
      ),
    ),
  );
}

class ModuleContent extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ModuleContent({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      BlinStyle.pagePadding,
      0,
      BlinStyle.pagePadding,
      BlinStyle.pagePadding,
    ),
  });

  @override
  Widget build(BuildContext context) => Padding(padding: padding, child: child);
}

class InfoLine extends StatelessWidget {
  final Widget avatar;
  final String title;
  final String? subtitle;
  final String? meta;
  final Widget? trailing;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final TextStyle? metaStyle;

  const InfoLine({
    super.key,
    required this.avatar,
    required this.title,
    this.subtitle,
    this.meta,
    this.trailing,
    this.titleStyle,
    this.subtitleStyle,
    this.metaStyle,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      avatar,
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle ?? Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle ?? Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (meta != null && meta!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                meta!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metaStyle ?? Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 12), trailing!],
    ],
  );
}
