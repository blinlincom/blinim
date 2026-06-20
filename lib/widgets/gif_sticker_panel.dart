import 'package:flutter/material.dart';

import 'blin_style.dart';

class GifSticker {
  final String id;
  final String label;
  final String asset;
  final String filename;

  const GifSticker({
    required this.id,
    required this.label,
    required this.asset,
    required this.filename,
  });
}

const builtInGifStickers = [
  GifSticker(
    id: 'pulse_heart',
    label: '比心',
    asset: 'assets/gif_stickers/pulse_heart.gif',
    filename: 'pulse_heart.gif',
  ),
  GifSticker(
    id: 'spark_star',
    label: '闪亮',
    asset: 'assets/gif_stickers/spark_star.gif',
    filename: 'spark_star.gif',
  ),
  GifSticker(
    id: 'thumbs_up',
    label: '点赞',
    asset: 'assets/gif_stickers/thumbs_up.gif',
    filename: 'thumbs_up.gif',
  ),
  GifSticker(
    id: 'smile_pop',
    label: '开心',
    asset: 'assets/gif_stickers/smile_pop.gif',
    filename: 'smile_pop.gif',
  ),
  GifSticker(
    id: 'ok_check',
    label: '收到',
    asset: 'assets/gif_stickers/ok_check.gif',
    filename: 'ok_check.gif',
  ),
  GifSticker(
    id: 'wave_hi',
    label: '打招呼',
    asset: 'assets/gif_stickers/wave_hi.gif',
    filename: 'wave_hi.gif',
  ),
  GifSticker(
    id: 'thanks_bloom',
    label: '感谢',
    asset: 'assets/gif_stickers/thanks_bloom.gif',
    filename: 'thanks_bloom.gif',
  ),
  GifSticker(
    id: 'message_ping',
    label: '提醒',
    asset: 'assets/gif_stickers/message_ping.gif',
    filename: 'message_ping.gif',
  ),
];

class ChatExpressionPanel extends StatefulWidget {
  final ValueChanged<String> onEmoji;
  final ValueChanged<GifSticker> onGif;
  final bool gifEnabled;
  final bool showGifTab;

  const ChatExpressionPanel({
    super.key,
    required this.onEmoji,
    required this.onGif,
    this.gifEnabled = true,
    this.showGifTab = false,
  });

  @override
  State<ChatExpressionPanel> createState() => _ChatExpressionPanelState();
}

class _ChatExpressionPanelState extends State<ChatExpressionPanel> {
  static const emojis = [
    '😀',
    '😂',
    '😊',
    '😍',
    '🥰',
    '😭',
    '😎',
    '👍',
    '👏',
    '🙏',
    '🎉',
    '🔥',
    '❤️',
    '💪',
    '🤔',
    '😅',
    '😡',
    '😴',
    '😋',
    '👌',
    '🌹',
    '🍻',
    '✨',
    '💯',
  ];

  int tab = 0;

  @override
  Widget build(BuildContext context) => Container(
    height: 214,
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
    decoration: BoxDecoration(
      color: BlinStyle.bg,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: BlinStyle.hairline(context, .45).color),
    ),
    child: Column(
      children: [
        Row(
          children: [
            _PanelTab(label: '表情', active: tab == 0, onTap: () => _setTab(0)),
            if (widget.showGifTab) ...[
              const SizedBox(width: 8),
              _PanelTab(
                label: 'GIF',
                active: tab == 1,
                onTap: () => _setTab(1),
              ),
            ],
            const Spacer(),
            Text(
              tab == 0 ? '点击插入输入框' : '点击直接发送动图',
              style: const TextStyle(
                color: BlinStyle.subtle,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: tab == 0 ? _emojiGrid() : _gifGrid()),
      ],
    ),
  );

  void _setTab(int value) {
    if (value == 1 && !widget.showGifTab) return;
    if (tab == value) return;
    setState(() => tab = value);
  }

  Widget _emojiGrid() => GridView.builder(
    primary: false,
    padding: EdgeInsets.zero,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: emojis.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 8,
      mainAxisExtent: 38,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
    ),
    itemBuilder: (_, i) => InkWell(
      onTap: () => widget.onEmoji(emojis[i]),
      borderRadius: BorderRadius.circular(10),
      child: Center(
        child: Text(emojis[i], style: const TextStyle(fontSize: 24)),
      ),
    ),
  );

  Widget _gifGrid() => GridView.builder(
    primary: false,
    padding: EdgeInsets.zero,
    itemCount: builtInGifStickers.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 4,
      mainAxisExtent: 72,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemBuilder: (_, i) {
      final sticker = builtInGifStickers[i];
      return InkWell(
        onTap: widget.gifEnabled ? () => widget.onGif(sticker) : null,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: BlinStyle.surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BlinStyle.hairline(context, .55).color),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Image.asset(
                    sticker.asset,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 5),
                child: Text(
                  sticker.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.gifEnabled
                        ? BlinStyle.textSecondary(context)
                        : BlinStyle.subtle,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PanelTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PanelTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: active ? BlinStyle.primary : BlinStyle.surface(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? BlinStyle.primary
              : BlinStyle.hairline(context, .55).color,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : BlinStyle.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
