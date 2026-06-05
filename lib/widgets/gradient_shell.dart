import 'package:flutter/material.dart';

class GradientShell extends StatelessWidget {
  final Widget child;
  const GradientShell({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F3EA), Color(0xFFEAF2FF), Color(0xFFF8E7EF)],
        ),
      ),
      child: Stack(children: [
        Positioned(top: -90, right: -70, child: _Orb(color: Color(0xFFFF7A59).withOpacity(.22), size: 240)),
        Positioned(bottom: -120, left: -70, child: _Orb(color: Color(0xFF1C7CFF).withOpacity(.16), size: 300)),
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
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color, blurRadius: 80, spreadRadius: 35)]));
}
