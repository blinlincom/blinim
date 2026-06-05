import 'package:flutter/material.dart';

class BlinStyle {
  static const bg = Color(0xFFF5F8FC);
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF7A8496);
  static const line = Color(0xFFE9EEF6);
  static const green = Color(0xFF20E38A);
  static const cyan = Color(0xFF42D9FF);
  static const blue = Color(0xFF4B7BFF);
  static const purple = Color(0xFF7C6CFF);
  static const orange = Color(0xFFFFB547);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1CE58E), Color(0xFF37D5FF), Color(0xFF4F7CFF)],
  );

  static BoxShadow softShadow([double opacity = .08]) => BoxShadow(
    color: const Color(0xFF0D2144).withValues(alpha: opacity),
    blurRadius: 24,
    offset: const Offset(0, 12),
  );
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
    this.radius = 24,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: .86)),
        boxShadow: [BlinStyle.softShadow()],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
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
      borderRadius: BorderRadius.circular(size * .38),
      boxShadow: [BlinStyle.softShadow(.14)],
    ),
    child: Icon(icon, color: Colors.white, size: iconSize),
  );
}

class PageBackdrop extends StatelessWidget {
  final Widget child;
  const PageBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    color: BlinStyle.bg,
    child: Stack(
      children: [
        Positioned(
          top: -120,
          right: -90,
          child: _Glow(
            color: BlinStyle.green.withValues(alpha: .24),
            size: 260,
          ),
        ),
        Positioned(
          top: 120,
          left: -120,
          child: _Glow(color: BlinStyle.cyan.withValues(alpha: .18), size: 240),
        ),
        child,
      ],
    ),
  );
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  const _Glow({required this.color, required this.size});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      boxShadow: [BoxShadow(color: color, blurRadius: 90, spreadRadius: 30)],
    ),
  );
}
