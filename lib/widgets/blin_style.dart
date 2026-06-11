import 'package:flutter/material.dart';

/// Blinlin visual system — Aurora social / communication identity.
///
/// UI-only: no business state, no API assumptions, no routing.
class BlinStyle {
  static const bg = Color(0xFFF2F6FF);
  static const bgElevated = Color(0xFFFFFFFF);
  static const darkBg = Color(0xFF060B18);
  static const darkSurface = Color(0xFF0F1828);
  static const ink = Color(0xFF101827);
  static const muted = Color(0xFF65738A);
  static const softInk = Color(0xFF2E3B52);
  static const line = Color(0xFFDDE7F5);
  static const darkLine = Color(0xFF24314A);

  static const green = Color(0xFF14E68B);
  static const cyan = Color(0xFF21D4FD);
  static const blue = Color(0xFF4068FF);
  static const purple = Color(0xFF8B5CFF);
  static const pink = Color(0xFFFF5FB7);
  static const orange = Color(0xFFFFA33A);
  static const danger = Color(0xFFFF4F68);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [green, cyan, blue, purple],
    stops: [0, .34, .68, 1],
  );

  static const auroraGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF07111F), Color(0xFF10285A), Color(0xFF3B1D6B)],
  );

  static const calmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF9FCFF), Color(0xFFEAF3FF), Color(0xFFF4EDFF)],
  );

  static BoxShadow softShadow([double opacity = .10]) => BoxShadow(
        color: const Color(0xFF0B1B35).withValues(alpha: opacity),
        blurRadius: 14,
        offset: const Offset(0, 7),
      );

  static BoxShadow glowShadow(Color color, [double opacity = .22]) => BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: 22,
        offset: const Offset(0, 10),
      );

  static BorderSide hairline(BuildContext context, [double opacity = 1]) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BorderSide(
      color: (dark ? darkLine : line).withValues(alpha: opacity),
    );
  }

  static Color surface(BuildContext context) => bgElevated;

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
    this.radius = 22,
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
        border: Border.all(color: Colors.white.withValues(alpha: .90)),
        boxShadow: [
          BlinStyle.softShadow(loud ? .14 : .075),
          if (loud) BlinStyle.glowShadow(BlinStyle.cyan, .10),
        ],
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
          borderRadius: BorderRadius.circular(size * .36),
          boxShadow: [BlinStyle.glowShadow(BlinStyle.cyan, .18)],
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
        gradient: dark ? BlinStyle.auroraGradient : BlinStyle.calmGradient,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -150,
            right: -120,
            child: _Glow(
              color: BlinStyle.cyan.withValues(alpha: dark ? .20 : .28),
              size: 310,
            ),
          ),
          Positioned(
            top: 130,
            left: -165,
            child: _Glow(
              color: BlinStyle.green.withValues(alpha: dark ? .16 : .18),
              size: 270,
            ),
          ),
          Positioned(
            bottom: -210,
            right: -150,
            child: _Glow(
              color: BlinStyle.purple.withValues(alpha: dark ? .20 : .18),
              size: 360,
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
              BoxShadow(color: color, blurRadius: 86, spreadRadius: 22),
            ],
          ),
        ),
      );
}
