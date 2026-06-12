import 'package:flutter/material.dart';
import 'blin_style.dart';

class GradientShell extends StatelessWidget {
  final Widget child;
  const GradientShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: BlinStyle.page(context)),
    child: child,
  );
}
