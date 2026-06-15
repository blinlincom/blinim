import 'package:flutter/material.dart';

/// Blinlin commercial IM visual system.
///
/// This file is UI-only. It keeps the old public class names so existing IM,
/// WebRTC and WuKongIM code can keep working while the visual layer changes.
class BlinStyle {
  static const primary = Color(0xFF2563EB);
  static const success = Color(0xFF00A862);
  static const warning = Color(0xFFF59E0B);

  static const bg = Color(0xFFF5F7FA);
  static const bgElevated = Color(0xFFFFFFFF);
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF5B6472);
  static const subtle = Color(0xFF9AA3AF);
  static const line = Color(0xFFE5E7EB);
  static const softFill = Color(0xFFF0F3F7);
  static const danger = Color(0xFFEF4444);

  static const darkBg = Color(0xFF111318);
  static const darkSurface = Color(0xFF1B1F27);
  static const darkLine = Color(0xFF303743);
  static const darkMuted = Color(0xFFCAD1DC);

  // Compatibility aliases used by older widgets.
  static const green = success;
  static const cyan = Color(0xFF0891B2);
  static const blue = primary;
  static const purple = Color(0xFF7C3AED);
  static const pink = Color(0xFFEC4899);
  static const orange = warning;
  static const softInk = ink;

  static const double pagePadding = 16;
  static const double moduleGap = 18;
  static const double verticalGap = 18;
  static const double compactGap = 12;
  static const double cardPadding = 16;
  static const double cardRadius = 8;
  static const double buttonRadius = 10;
  static const double iconSize = 24;

  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x0A000000),
    blurRadius: 10,
    offset: Offset(0, 3),
  );

  static BoxShadow softShadow([double opacity = .06]) => BoxShadow(
    color: Colors.black.withValues(alpha: opacity.clamp(.03, .12)),
    blurRadius: 18,
    offset: const Offset(0, 8),
  );

  static BoxShadow glowShadow(Color color, [double opacity = .10]) => BoxShadow(
    color: color.withValues(alpha: opacity.clamp(.04, .16)),
    blurRadius: 18,
    offset: const Offset(0, 8),
  );

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

  static Color textPrimary(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? bg : ink;
  }

  static Color textSecondary(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? darkMuted : muted;
  }

  static Color iconSurface(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? const Color(0xFF263449) : softFill;
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
    final surface = color ?? BlinStyle.surface(context);
    final box = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: borderRadius,
        border: Border.all(
          color: loud
              ? BlinStyle.primary.withValues(alpha: .30)
              : BlinStyle.hairline(context, .82).color,
        ),
        boxShadow: loud
            ? const [BlinStyle.cardShadow]
            : const [BlinStyle.cardShadow],
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
      color: BlinStyle.primary.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
      border: Border.all(color: BlinStyle.primary.withValues(alpha: .18)),
    ),
    child: Icon(icon, color: BlinStyle.primary, size: iconSize),
  );
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: BlinStyle.primary,
      borderRadius: BorderRadius.circular(size * .22),
      boxShadow: const [BlinStyle.cardShadow],
    ),
    child: Icon(
      Icons.forum_rounded,
      color: Theme.of(context).colorScheme.onPrimary,
      size: size * .52,
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
      decoration: BoxDecoration(
        color: BlinStyle.surface(context),
        border: Border(
          bottom: BorderSide(color: BlinStyle.hairline(context, .82).color),
        ),
      ),
      child: Padding(
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
                    const SizedBox(height: 3),
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
              Wrap(
                spacing: 6,
                children: actions
                    .map(
                      (child) => Container(
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        decoration: BoxDecoration(
                          color: BlinStyle.iconSurface(context),
                          borderRadius: BorderRadius.circular(
                            BlinStyle.buttonRadius,
                          ),
                          border: Border.all(
                            color: BlinStyle.hairline(context, .72).color,
                          ),
                        ),
                        child: Center(child: child),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 3),
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
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
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

class AppAvatar extends StatelessWidget {
  final String imageUrl;
  final String name;
  final double size;
  final bool online;
  final bool showOnline;
  final IconData? fallbackIcon;

  const AppAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.size = 52,
    this.online = false,
    this.showOnline = false,
    this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * .34);
    final fallback = name.characters.isEmpty ? '?' : name.characters.first;
    final fallbackChild = Center(
      child: fallbackIcon == null
          ? Text(
              fallback,
              style: TextStyle(
                color: BlinStyle.primary,
                fontSize: size * .34,
                fontWeight: FontWeight.w600,
              ),
            )
          : Icon(fallbackIcon, color: BlinStyle.primary, size: size * .48),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: BlinStyle.primary.withValues(alpha: .08),
            borderRadius: radius,
            border: Border.all(color: BlinStyle.hairline(context, .75).color),
          ),
          clipBehavior: Clip.antiAlias,
          child: imageUrl.trim().isNotEmpty
              ? Image.network(
                  imageUrl.trim(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallbackChild,
                )
              : fallbackChild,
        ),
        if (showOnline)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: size * .24,
              height: size * .24,
              decoration: BoxDecoration(
                color: online ? BlinStyle.success : BlinStyle.subtle,
                shape: BoxShape.circle,
                border: Border.all(color: BlinStyle.surface(context), width: 2),
              ),
            ),
          ),
      ],
    );
  }
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

class ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final int badge;
  final bool selected;

  const ActionPill({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.badge = 0,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? BlinStyle.primary.withValues(alpha: .10)
        : BlinStyle.iconSurface(context);
    final fg = selected ? BlinStyle.primary : BlinStyle.textPrimary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
            border: Border.all(color: BlinStyle.hairline(context, .76).color),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: fg, size: 20),
                  if (badge > 0)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Badge(
                        label: Text(badge > 99 ? '99+' : '$badge'),
                        smallSize: 8,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
