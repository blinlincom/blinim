import 'package:flutter/material.dart';

import '../utils/media_url.dart';

/// Blinlin IM visual system.
///
/// This file is UI-only. It keeps the old public class names so existing IM,
/// WebRTC and WuKongIM code can keep working while the visual layer changes.
class BlinStyle {
  static const primary = Color(0xFF1E3A5F);
  static const primaryStrong = Color(0xFF0F2742);
  static const primarySoft = Color(0xFFEAF0F7);
  static const success = Color(0xFF059669);
  static const warning = Color(0xFFD97706);
  static const commerce = Color(0xFF2563EB);
  static const redPacket = Color(0xFFB91C1C);
  static const redPacketSoft = Color(0xFFFFE8E1);

  static const bg = Color(0xFFF8FAFC);
  static const bgElevated = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF475569);
  static const subtle = Color(0xFF94A3B8);
  static const line = Color(0xFFE4E7EB);
  static const softFill = Color(0xFFF1F5F9);
  static const wash = Color(0xFFF6F8FB);
  static const danger = Color(0xFFDC2626);
  static const tabSelected = primary;
  static const tabNormal = Color(0xFF94A3B8);
  static const sentBubble = Color(0xFFE7EEFF);
  static const sentBubbleBorder = Color(0xFFC9D7FF);

  static const darkBg = Color(0xFF0B1220);
  static const darkSurface = Color(0xFF111827);
  static const darkLine = Color(0xFF253044);
  static const darkMuted = Color(0xFFCAD1DC);

  // Compatibility aliases used by older widgets.
  static const green = success;
  static const cyan = Color(0xFF0891B2);
  static const blue = Color(0xFF2563EB);
  static const purple = Color(0xFF7C3AED);
  static const pink = Color(0xFFEC4899);
  static const orange = warning;
  static const softInk = ink;

  static const double pagePadding = 20;
  static const double moduleGap = 24;
  static const double verticalGap = 12;
  static const double compactGap = 12;
  static const double cardPadding = 16;
  static const double cardRadius = 18;
  static const double buttonRadius = 16;
  static const double iconSize = 24;
  static const double navRadius = 24;
  static const double maxContentWidth = 900;

  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x100F172A),
    blurRadius: 14,
    offset: Offset(0, 6),
  );

  static const BoxShadow flatShadow = BoxShadow(
    color: Color(0x080F172A),
    blurRadius: 10,
    offset: Offset(0, 2),
  );

  static Color parseColor(Object? value, [Color fallback = primary]) {
    if (value == null) return fallback;
    if (value is Color) return value;
    var text = '$value'.trim();
    if (text.isEmpty) return fallback;
    final lower = text.toLowerCase();
    if (lower == 'null' || lower == 'undefined') return fallback;
    text = text.replaceAll(RegExp(r'^(0x|#)', caseSensitive: false), '');
    if (text.length == 3) {
      text = text.split('').map((c) => '$c$c').join();
    }
    if (text.length == 6) {
      text = 'ff$text';
    }
    if (text.length != 8) return fallback;
    final parsed = int.tryParse(text, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
  }

  static Color parseTitleColor(Object? value, [Color fallback = primary]) {
    return parseColor(value, fallback);
  }

  static BoxShadow softShadow([double opacity = .06]) => BoxShadow(
    color: Colors.black.withValues(alpha: opacity.clamp(.03, .08)),
    blurRadius: 14,
    offset: const Offset(0, 6),
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

  static Color rowPressed(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? const Color(0xFF24272D) : const Color(0xFFEFF2F8);
  }

  static EdgeInsets pageInsets(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1200) return const EdgeInsets.symmetric(horizontal: 32);
    if (width >= 720) return const EdgeInsets.symmetric(horizontal: 24);
    return const EdgeInsets.symmetric(horizontal: pagePadding);
  }
}

class _TitleNameParts {
  final String name;
  final String title;
  const _TitleNameParts({required this.name, required this.title});
}

_TitleNameParts? _splitTitledName(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final patterns = <RegExp>[
    RegExp(r'^(.*?)[\s]*\[(.+)\][\s]*$'),
    RegExp(r'^(.*?)[\s]*【(.+)】[\s]*$'),
    RegExp(r'^(.*?)[\s]*\((.+)\)[\s]*$'),
    RegExp(r'^(.*?)[\s]*（(.+)）[\s]*$'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    final name = (match.group(1) ?? '').trim();
    final title = (match.group(2) ?? '').trim();
    if (title.isNotEmpty) {
      return _TitleNameParts(name: name.isEmpty ? '用户' : name, title: title);
    }
  }
  return null;
}

class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double radius;
  final VoidCallback? onTap;
  final bool loud;
  final Clip clipBehavior;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color,
    this.radius = BlinStyle.cardRadius,
    this.onTap,
    this.loud = false,
    this.clipBehavior = Clip.none,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final surface = color ?? BlinStyle.surface(context);
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: borderRadius,
        border: Border.all(
          color: loud
              ? BlinStyle.primary.withValues(alpha: .30)
              : BlinStyle.hairline(context, .54).color,
        ),
        boxShadow: loud
            ? [BlinStyle.glowShadow(BlinStyle.primary, .08)]
            : const [BlinStyle.flatShadow],
      ),
      clipBehavior: clipBehavior,
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: borderRadius, onTap: onTap, child: box),
    );
  }
}

class SoftAppear extends StatelessWidget {
  final Widget child;
  final int index;
  final double distance;
  final Duration duration;

  const SoftAppear({
    super.key,
    required this.child,
    this.index = 0,
    this.distance = 10,
    this.duration = const Duration(milliseconds: 220),
  });

  @override
  Widget build(BuildContext context) {
    final motion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (motion) return child;
    final extra = Duration(milliseconds: (index.clamp(0, 8) * 18).round());
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration + extra,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * distance),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class BlinRefresh extends StatelessWidget {
  final Widget child;
  final RefreshCallback onRefresh;
  final double displacement;
  final double edgeOffset;
  final ScrollNotificationPredicate notificationPredicate;

  const BlinRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 44,
    this.edgeOffset = 6,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: displacement,
      edgeOffset: edgeOffset,
      strokeWidth: 2.6,
      color: BlinStyle.primary,
      backgroundColor: dark ? const Color(0xFF202631) : Colors.white,
      elevation: 4,
      notificationPredicate: notificationPredicate,
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      child: child,
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
      color: BlinStyle.primary,
      borderRadius: BorderRadius.circular(size * .30),
      boxShadow: [
        BoxShadow(
          color: BlinStyle.primary.withValues(alpha: .16),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Icon(icon, color: Colors.white, size: iconSize),
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
      borderRadius: BorderRadius.circular(size * .28),
      boxShadow: const [BlinStyle.cardShadow],
    ),
    child: Icon(
      Icons.chat_bubble_outline_rounded,
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

class ContentMaxWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  const ContentMaxWidth({
    super.key,
    required this.child,
    this.maxWidth = BlinStyle.maxContentWidth,
    this.alignment = Alignment.topCenter,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class AppTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? leading;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.actions = const [],
    this.padding = const EdgeInsets.symmetric(
      horizontal: BlinStyle.pagePadding,
    ),
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Container(
      decoration: BoxDecoration(
        color: BlinStyle.page(context),
        border: Border(
          bottom: BorderSide(color: BlinStyle.hairline(context, .42).color),
        ),
      ),
      child: ContentMaxWidth(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: subtitleWidget == null && subtitle == null ? 62 : 74,
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: BlinStyle.textPrimary(context),
                            fontSize: 22,
                            height: 1.08,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitleWidget != null) ...[
                          const SizedBox(height: 5),
                          subtitleWidget!,
                        ] else if (subtitle != null &&
                            subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 5),
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
                  if (actions.isNotEmpty) Wrap(spacing: 8, children: actions),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class NativeIconBox extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  const NativeIconBox({
    super.key,
    required this.icon,
    this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: (color ?? BlinStyle.primary).withValues(alpha: .11),
      borderRadius: BorderRadius.circular(size * .34),
      border: Border.all(
        color: (color ?? BlinStyle.primary).withValues(alpha: .14),
      ),
    ),
    child: Icon(icon, color: color ?? BlinStyle.primary, size: size * .52),
  );
}

class BlinAssetIconButton extends StatelessWidget {
  final String asset;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  final double size;
  final double iconSize;

  const BlinAssetIconButton({
    super.key,
    required this.asset,
    required this.onTap,
    this.tooltip,
    this.color,
    this.size = 40,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? BlinStyle.textPrimary(context);
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: BlinStyle.iconSurface(context),
            borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
            border: Border.all(color: BlinStyle.hairline(context, .55).color),
          ),
          child: Center(
            child: Image.asset(
              asset,
              width: iconSize,
              height: iconSize,
              fit: BoxFit.contain,
              color: tint,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class NativeListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? subtitleWidget;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final double minHeight;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  const NativeListRow({
    super.key,
    required this.leading,
    required this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.meta,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.padding = const EdgeInsets.fromLTRB(14, 8, 12, 8),
    this.minHeight = 72,
    this.titleStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final parsedTitle = _splitTitledName(title);
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: padding,
      decoration: BoxDecoration(
        color: selected
            ? BlinStyle.primary.withValues(alpha: .08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child:
                          titleWidget ??
                          (parsedTitle == null
                              ? Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      titleStyle ??
                                      TextStyle(
                                        color: BlinStyle.textPrimary(context),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                )
                              : NameTitleText(
                                  name: parsedTitle.name,
                                  title: parsedTitle.title,
                                  style: titleStyle,
                                )),
                    ),
                    if (meta != null && meta!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        meta!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: BlinStyle.subtle,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitleWidget != null) ...[
                  const SizedBox(height: 3),
                  subtitleWidget!,
                ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        subtitleStyle ??
                        const TextStyle(
                          color: BlinStyle.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: content,
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) =>
      ContentMaxWidth(padding: padding, child: child);
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
    final radius = BorderRadius.circular(size * .30);
    final fallback = name.characters.isEmpty ? '?' : name.characters.first;
    final resolvedImageUrl = resolveMediaUrl(imageUrl);
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
            color: BlinStyle.primarySoft,
            borderRadius: radius,
            border: Border.all(color: BlinStyle.hairline(context, .75).color),
          ),
          clipBehavior: Clip.antiAlias,
          child: resolvedImageUrl.isNotEmpty
              ? Image.network(
                  resolvedImageUrl,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const SizedBox.expand(),
                  errorBuilder: (_, _, _) => fallbackChild,
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

class ShellAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool selected;

  const ShellAction({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? BlinStyle.primary : BlinStyle.textPrimary(context);
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected
                ? BlinStyle.primary.withValues(alpha: .10)
                : BlinStyle.iconSurface(context),
            borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
            border: Border.all(color: BlinStyle.hairline(context, .55).color),
          ),
          child: Icon(icon, color: fg, size: 22),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class ProductSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmitted;
  final bool readOnly;
  final Widget? trailing;

  const ProductSearchField({
    super.key,
    this.controller,
    required this.hintText,
    this.onTap,
    this.onSubmitted,
    this.readOnly = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    decoration: BoxDecoration(
      color: BlinStyle.surface(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: BlinStyle.hairline(context, .56).color),
      boxShadow: const [BlinStyle.flatShadow],
    ),
    child: TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded, size: 22),
        suffixIcon: trailing,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    ),
  );
}

class ProductEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const ProductEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(BlinStyle.pagePadding),
      child: SoftCard(
        color: BlinStyle.surface(context),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NativeIconBox(icon: icon, color: BlinStyle.primary, size: 58),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ),
  );
}

class InfoLine extends StatelessWidget {
  final Widget avatar;
  final String title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? subtitleWidget;
  final String? meta;
  final Widget? trailing;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final TextStyle? metaStyle;

  const InfoLine({
    super.key,
    required this.avatar,
    required this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
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
            titleWidget ??
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle ?? Theme.of(context).textTheme.titleMedium,
                ),
            if (subtitleWidget != null) ...[
              const SizedBox(height: 4),
              subtitleWidget!,
            ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
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

class NameTitleText extends StatelessWidget {
  final String name;
  final String title;
  final Object? titleColor;
  final TextStyle? style;
  final TextStyle? titleStyle;
  final int maxLines;

  const NameTitleText({
    super.key,
    required this.name,
    this.title = '',
    this.titleColor,
    this.style,
    this.titleStyle,
    this.maxLines = 1,
  });

  String _cleanTitle(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';
    final lower = text.toLowerCase();
    if (lower == 'null' || lower == 'undefined' || lower == 'false') return '';
    if (text == '0' || text == '--' || text == '-' || text == '[]') return '';
    text = text
        .replaceAll(RegExp(r'^[\[\]【】（）()\s]+'), '')
        .replaceAll(RegExp(r'[\[\]【】（）()\s]+$'), '')
        .trim();
    if (text.isEmpty || text == '0' || text == '--' || text == '-') return '';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final cleanName = name.trim().isEmpty ? '用户' : name.trim();
    final cleanTitle = _cleanTitle(title);
    final baseStyle =
        style ??
        Theme.of(context).textTheme.titleMedium?.copyWith(
          color: BlinStyle.textPrimary(context),
          fontWeight: FontWeight.w600,
        ) ??
        TextStyle(
          color: BlinStyle.textPrimary(context),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        );
    if (cleanTitle.isEmpty) {
      return Text(
        cleanName,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: cleanName, style: baseStyle),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TitleBadge(
                text: cleanTitle,
                color: titleColor,
                textStyle: titleStyle,
              ),
            ),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class TitleBadge extends StatelessWidget {
  final String text;
  final Object? color;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry padding;

  const TitleBadge({
    super.key,
    required this.text,
    this.color,
    this.textStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  });

  String _clean(String value) {
    var result = value.trim();
    if (result.isEmpty) return '';
    final lower = result.toLowerCase();
    if (lower == 'null' || lower == 'undefined' || lower == 'false') return '';
    if (result == '0' || result == '--' || result == '-' || result == '[]') {
      return '';
    }
    result = result
        .replaceAll(RegExp(r'^[\[\]【】（）()\s]+'), '')
        .replaceAll(RegExp(r'[\[\]【】（）()\s]+$'), '')
        .trim();
    if (result.isEmpty || result == '0' || result == '--' || result == '-') {
      return '';
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final value = _clean(text);
    if (value.isEmpty) return const SizedBox.shrink();
    final badgeColor = BlinStyle.parseColor(color, BlinStyle.warning);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bgAlpha = dark ? .24 : .12;
    final borderAlpha = dark ? .38 : .20;
    final baseTextStyle =
        textStyle ??
        Theme.of(context).textTheme.labelSmall ??
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
    return Container(
      constraints: const BoxConstraints(minHeight: 19, maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: badgeColor.withValues(alpha: borderAlpha)),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseTextStyle.copyWith(
          color: badgeColor,
          fontSize: 10.5,
          height: 1.05,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
