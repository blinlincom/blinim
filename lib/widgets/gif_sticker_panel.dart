import 'package:flutter/material.dart';

import '../utils/media_url.dart' as media_url;
import 'blin_style.dart';

class GifSticker {
  final String id;
  final String label;
  final String asset;
  final String filename;
  final String url;
  final String thumbnailUrl;
  final String packId;
  final String packName;
  final String packCoverUrl;
  final int packSort;
  final int width;
  final int height;
  final String format;

  const GifSticker({
    required this.id,
    required this.label,
    this.asset = '',
    required this.filename,
    this.url = '',
    this.thumbnailUrl = '',
    this.packId = '',
    this.packName = '',
    this.packCoverUrl = '',
    this.packSort = 0,
    this.width = 0,
    this.height = 0,
    this.format = '',
  });

  bool get isNetwork => url.trim().isNotEmpty;
  bool get isGif =>
      _normalizedFormat == 'gif' ||
      _looksLikeGif(url) ||
      _looksLikeGif(filename) ||
      _looksLikeGif(asset);
  bool get isStaticSticker => !isGif;
  String get messageType => isGif ? 'gif' : 'sticker';
  String get fallbackContent => isGif ? '[GIF]' : '[表情]';
  String get mediaFormat => isGif ? 'gif' : _staticFormat;
  String get displayUrl {
    final thumb = thumbnailUrl.trim();
    if (thumb.isNotEmpty) return thumb;
    return url;
  }

  String get effectivePackId {
    final value = packId.trim();
    if (value.isNotEmpty) return value;
    return isNetwork ? id : 'builtin';
  }

  String get effectivePackName {
    final value = packName.trim();
    if (value.isNotEmpty) return value;
    return isNetwork ? '表情包' : '默认表情';
  }

  String get packDisplayUrl {
    final value = packCoverUrl.trim();
    if (value.isNotEmpty) return value;
    return displayUrl;
  }

  String get _normalizedFormat {
    final text = format.trim().toLowerCase();
    if (text == 'jpg') return 'jpeg';
    return text;
  }

  String get _staticFormat {
    final direct = _normalizedFormat;
    if (direct.isNotEmpty && direct != 'gif' && direct != 'sticker') {
      return direct;
    }
    final ext = _extensionFrom(url).isNotEmpty
        ? _extensionFrom(url)
        : _extensionFrom(filename);
    return ext.isEmpty || ext == 'gif' ? 'sticker' : ext;
  }

  static String _extensionFrom(String value) {
    final clean = value.split('?').first.split('#').first.toLowerCase();
    final index = clean.lastIndexOf('.');
    if (index < 0 || index == clean.length - 1) return '';
    return clean.substring(index + 1);
  }

  static bool _looksLikeGif(String value) => _extensionFrom(value) == 'gif';

  factory GifSticker.fromStoreRow(Map<String, dynamic> row, {int index = 0}) {
    String pick(List<String> keys, [String fallback = '']) {
      for (final key in keys) {
        final value = '${row[key] ?? ''}'.trim();
        if (value.isNotEmpty && value != 'null') return value;
      }
      return fallback;
    }

    int pickInt(List<String> keys) {
      for (final key in keys) {
        final value = row[key];
        if (value is num) return value.toInt();
        final parsed = int.tryParse('${value ?? ''}');
        if (parsed != null) return parsed;
      }
      return 0;
    }

    String firstUrl(String raw) {
      var value = '';
      for (final item in raw.split(RegExp(r'[,，\s]+'))) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty && trimmed != 'null') {
          value = trimmed;
          break;
        }
      }
      return media_url.resolveMediaUrl(value);
    }

    final rawUrl = pick([
      'gif_url',
      'sticker_url',
      'download',
      'url',
      'file_url',
      'image_path',
      'app_introduction_image',
    ]);
    final resolvedUrl = firstUrl(rawUrl);
    final rawThumbnail = pick([
      'thumb',
      'thumbnail',
      'thumbnail_url',
      'preview_url',
      'cover',
      'app_icon',
      'icon',
      'app_introduction_image',
    ]);
    final resolvedThumbnail = firstUrl(rawThumbnail);
    final rawPackCover = pick([
      'pack_cover',
      'emoji_pack_cover',
      'package_cover',
      'package_cover_url',
      'app_icon',
      'cover',
      'preview_url',
      'thumb',
      'thumbnail_url',
      'app_introduction_image',
    ]);
    final resolvedPackCover = firstUrl(rawPackCover);
    final rawPackId = pick([
      'pack_id',
      'emoji_pack_id',
      'package_id',
      'apps_id',
      'app_id',
    ]);
    final rawPackName = pick([
      'pack_name',
      'emoji_pack_name',
      'package_name',
      'bundle_name',
    ]);
    final label = pick([
      'emoji_name',
      'sticker_name',
      'appname',
      'app_name',
      'product_name',
      'title',
      'label',
      'name',
    ], '动图${index + 1}');
    final parsedPath = Uri.tryParse(resolvedUrl)?.path ?? resolvedUrl;
    final pathParts = parsedPath
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .toList();
    final inferredName = pathParts.isEmpty ? null : pathParts.last;
    final filename = pick([
      'filename',
      'file_name',
      'package_name',
    ], inferredName ?? 'emoji_${index + 1}.gif');
    final rawFormat = pick([
      'media_format',
      'format',
      'file_format',
      'extension',
      'ext',
      'sticker_type',
    ]);
    final isGifFlag = pick(['is_gif', 'animated']).toLowerCase();
    final inferredFormat = isGifFlag == '1' || isGifFlag == 'true'
        ? 'gif'
        : rawFormat.isNotEmpty
        ? rawFormat
        : _extensionFrom(filename).isNotEmpty
        ? _extensionFrom(filename)
        : _extensionFrom(resolvedUrl);
    return GifSticker(
      id: pick(['sticker_id', 'emoji_id', 'id'], 'store_$index'),
      label: label,
      filename: filename,
      url: resolvedUrl,
      thumbnailUrl: resolvedThumbnail,
      packId: rawPackId,
      packName: rawPackName,
      packCoverUrl: resolvedPackCover,
      packSort: pickInt(['pack_sort', 'sticker_sort', 'sort', 'sort_order']),
      width: pickInt(['width', 'image_width']),
      height: pickInt(['height', 'image_height']),
      format: inferredFormat,
    );
  }
}

class GifStickerPack {
  final String id;
  final String name;
  final String coverUrl;
  final List<GifSticker> stickers;

  const GifStickerPack({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.stickers,
  });

  GifSticker get coverSticker => stickers.first;
  String get displayUrl {
    final cover = coverUrl.trim();
    if (cover.isNotEmpty) return cover;
    return coverSticker.packDisplayUrl;
  }
}

List<GifStickerPack> groupGifStickerPacks(List<GifSticker> stickers) {
  final grouped = <String, List<GifSticker>>{};
  for (final sticker in stickers) {
    grouped
        .putIfAbsent(sticker.effectivePackId, () => <GifSticker>[])
        .add(sticker);
  }
  return grouped.entries.map((entry) {
    final list = [...entry.value]
      ..sort((a, b) => a.packSort.compareTo(b.packSort));
    final first = list.first;
    final cover = list
        .map((item) => item.packDisplayUrl)
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    return GifStickerPack(
      id: entry.key,
      name: first.effectivePackName,
      coverUrl: cover,
      stickers: list,
    );
  }).toList();
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
  final List<GifSticker> gifStickers;
  final bool gifEnabled;
  final bool showGifTab;

  const ChatExpressionPanel({
    super.key,
    required this.onEmoji,
    required this.onGif,
    this.gifStickers = builtInGifStickers,
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
  String selectedPackId = '';

  @override
  void didUpdateWidget(covariant ChatExpressionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final exists = groupGifStickerPacks(
      widget.gifStickers,
    ).any((item) => item.id == selectedPackId);
    if (!exists && selectedPackId.isNotEmpty) selectedPackId = '';
  }

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
                label: '表情包',
                active: tab == 1,
                onTap: () => _setTab(1),
              ),
            ],
            const Spacer(),
            Text(
              tab == 0 ? '点击插入输入框' : '上方切换表情包',
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
    setState(() {
      tab = value;
    });
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

  Widget _gifGrid() {
    final packs = groupGifStickerPacks(widget.gifStickers);
    if (packs.isEmpty) {
      return const Center(
        child: Text(
          '暂无表情包',
          style: TextStyle(
            color: BlinStyle.subtle,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final pack = packs.firstWhere(
      (item) => item.id == selectedPackId,
      orElse: () => packs.first,
    );
    return Column(
      children: [
        SizedBox(height: 48, child: _packStrip(packs, pack.id)),
        const SizedBox(height: 8),
        Expanded(child: _stickerGrid(pack.stickers)),
      ],
    );
  }

  Widget _packStrip(List<GifStickerPack> packs, String activeId) =>
      ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: packs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final pack = packs[i];
          final active = pack.id == activeId;
          return InkWell(
            onTap: widget.gifEnabled
                ? () => setState(() => selectedPackId = pack.id)
                : null,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: active
                    ? BlinStyle.primary.withValues(alpha: .10)
                    : BlinStyle.surface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active
                      ? BlinStyle.primary
                      : BlinStyle.hairline(context, .55).color,
                  width: active ? 1.4 : 1,
                ),
              ),
              child: _StickerImage(
                imageUrl: pack.displayUrl,
                asset: pack.coverSticker.asset,
                isNetwork: pack.coverSticker.isNetwork,
              ),
            ),
          );
        },
      );

  Widget _stickerGrid(List<GifSticker> stickers) => GridView.builder(
    primary: false,
    padding: EdgeInsets.zero,
    itemCount: stickers.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 4,
      mainAxisExtent: 72,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemBuilder: (_, i) {
      final sticker = stickers[i];
      return InkWell(
        onTap: widget.gifEnabled ? () => widget.onGif(sticker) : null,
        borderRadius: BorderRadius.circular(16),
        child: _StickerTile(
          imageUrl: sticker.displayUrl,
          asset: sticker.asset,
          isNetwork: sticker.isNetwork,
          label: sticker.label,
          enabled: widget.gifEnabled,
        ),
      );
    },
  );
}

class _StickerImage extends StatelessWidget {
  final String imageUrl;
  final String asset;
  final bool isNetwork;

  const _StickerImage({
    required this.imageUrl,
    required this.asset,
    required this.isNetwork,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(11),
    child: isNetwork
        ? Image.network(
            imageUrl,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: BlinStyle.subtle,
            ),
          )
        : Image.asset(
            asset,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            fit: BoxFit.contain,
          ),
  );
}

class _StickerTile extends StatelessWidget {
  final String imageUrl;
  final String asset;
  final bool isNetwork;
  final String label;
  final bool enabled;

  const _StickerTile({
    required this.imageUrl,
    required this.asset,
    required this.isNetwork,
    required this.label,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) => Ink(
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
            child: _StickerImage(
              imageUrl: imageUrl,
              asset: asset,
              isNetwork: isNetwork,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 5),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: enabled
                  ? BlinStyle.textSecondary(context)
                  : BlinStyle.subtle,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
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
