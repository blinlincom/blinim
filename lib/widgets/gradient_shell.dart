import 'package:flutter/material.dart';
import 'blin_style.dart';

class GradientShell extends StatelessWidget {
  final Widget child;
  const GradientShell({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BlinStyle.page(context),
        gradient: dark ? null : BlinStyle.calmGradient,
      ),
      child: Stack(children: [
        Positioned(
          top: -110,
          right: -86,
          child: _Orb(
            color: BlinStyle.green.withValues(alpha: dark ? .09 : .14),
            size: 260,
          ),
        ),
        Positioned(
          bottom: -135,
          left: -90,
          child: _Orb(
            color: BlinStyle.blue.withValues(alpha: dark ? .08 : .11),
            size: 315,
          ),
        ),
        child,
      ]),
    );
  }
}

class _Orb extends StatelessWidget {
  final Color color;
  final double size;
  const _Orb({required this.color, required this.size});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [BoxShadow(color: color, blurRadius: 72, spreadRadius: 20)],
          ),
        ),
      );
}
