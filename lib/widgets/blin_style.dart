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

  static const double pagePadding = 16;
  static const double verticalGap = 12;
  static const double cardRadius = 20;
  static const double buttonRadius = 16;
  static const double iconSize = 24;

  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x0F000000),
    blurRadius: 10,
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
      color: Theme.of(context).colorScheme.primary,
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
