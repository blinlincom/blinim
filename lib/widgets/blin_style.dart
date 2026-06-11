import 'package:flutter/material.dart';

/// Central visual language for the client.
///
/// Keep this file UI-only: no business state, no API assumptions, no routing.
class BlinStyle {
  static const bg = Color(0xFFF4F7FB);
  static const bgElevated = Color(0xFFFFFFFF);
  static const darkBg = Color(0xFF07111F);
  static const darkSurface = Color(0xFF0E1929);
  static const ink = Color(0xFF1F2A3D);
  static const muted = Color(0xFF6F7D91);
  static const softInk = Color(0xFF42526A);
  static const line = Color(0xFFE3EAF3);
  static const darkLine = Color(0xFF1E3048);
  static const green = Color(0xFF16D982);
  static const cyan = Color(0xFF35CFFF);
  static const blue = Color(0xFF426BFF);
  static const purple = Color(0xFF7568FF);
  static const orange = Color(0xFFFFA93D);
  static const danger = Color(0xFFFF5C6C);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF16D982), Color(0xFF35CFFF), Color(0xFF426BFF)],
  );

  static const calmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8FBFF), Color(0xFFEFF5FF), Color(0xFFF7FAFD)],
  );

  static BoxShadow softShadow([double opacity = .07]) => BoxShadow(
        color: const Color(0xFF10233F).withValues(alpha: opacity),
        blurRadius: 10,
        offset: const Offset(0, 5),
      );

  static BorderSide hairline(BuildContext context, [double opacity = 1]) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BorderSide(
      color: (dark ? darkLine : line).withValues(alpha: opacity),
    );
  }

  static Color surface(BuildContext context) {
    // Most existing business widgets use const BlinStyle.ink text.
    // Keep cards light by default so UI modernization does not break readability.
    return bgElevated;
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

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color,
    this.radius = 18,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);
    final box = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? BlinStyle.surface(context),
        borderRadius: borderRadius,
        border: Border.all(
          color: (dark ? BlinStyle.darkLine : Colors.white)
              .withValues(alpha: dark ? .92 : .88),
        ),
        boxShadow: dark ? const [] : [BlinStyle.softShadow()],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: box,
      ),
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
          gradient: BlinStyle.brandGradient,
          borderRadius: BorderRadius.circular(size * .34),
          boxShadow: [BlinStyle.softShadow(.13)],
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      );
}

class PageBackdrop extends StatelessWidget {
  final Widget child;
  const PageBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BlinStyle.page(context),
        gradient: dark ? null : BlinStyle.calmGradient,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -135,
            right: -115,
            child: _Glow(
              color: BlinStyle.green.withValues(alpha: dark ? .10 : .16),
              size: 280,
            ),
          ),
          Positioned(
            top: 180,
            left: -150,
            child: _Glow(
              color: BlinStyle.cyan.withValues(alpha: dark ? .08 : .12),
              size: 260,
            ),
          ),
          Positioned(
            bottom: -170,
            right: -160,
            child: _Glow(
              color: BlinStyle.blue.withValues(alpha: dark ? .08 : .10),
              size: 320,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  const _Glow({required this.color, required this.size});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color, blurRadius: 72, spreadRadius: 18),
            ],
          ),
        ),
      );
}
