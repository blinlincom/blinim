import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'blin_style.dart';

final RegExp appLinkPattern = RegExp(
  r'((https?:\/\/|www\.)[^\s<>"'
  '，。！？、；：]+)',
  caseSensitive: false,
);

Uri? normalizeAppLink(String raw) {
  var text = raw.trim();
  while (text.endsWith('.') ||
      text.endsWith(',') ||
      text.endsWith('，') ||
      text.endsWith('。') ||
      text.endsWith('!') ||
      text.endsWith('！') ||
      text.endsWith('?') ||
      text.endsWith('？') ||
      text.endsWith(')') ||
      text.endsWith('）')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.startsWith('www.')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

class LinkText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final ValueChanged<Uri> onOpenLink;

  const LinkText({
    super.key,
    required this.text,
    required this.onOpenLink,
    this.style,
    this.linkStyle,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        style ??
        const TextStyle(
          color: BlinStyle.ink,
          height: 1.35,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        );
    final effectiveLinkStyle =
        linkStyle ??
        baseStyle.copyWith(
          color: BlinStyle.primary,
          decoration: TextDecoration.underline,
          decorationColor: BlinStyle.primary,
        );
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in appLinkPattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      final raw = match.group(0) ?? '';
      final uri = normalizeAppLink(raw);
      spans.add(
        TextSpan(
          text: raw,
          style: uri == null ? baseStyle : effectiveLinkStyle,
          recognizer: uri == null
              ? null
              : (TapGestureRecognizer()..onTap = () => onOpenLink(uri)),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    if (spans.isEmpty) return Text(text, style: baseStyle);
    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}
