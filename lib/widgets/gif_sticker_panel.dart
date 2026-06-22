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
      _normalizedFormat == 'animated' ||
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
      'thumb_url',
      'thumbnail_url',
      'cover_url',
      'cover_image',
      'cover_image_url',
      'first_image',
      'first_image_url',
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
      'cover_url',
      'cover_image',
      'cover_image_url',
      'first_image',
      'first_image_url',
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
      'type',
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
    final firstSticker = coverSticker.displayUrl.trim();
    if (firstSticker.isNotEmpty) return firstSticker;
    final cover = coverUrl.trim();
    if (cover.isNotEmpty) return cover;
    return coverSticker.packDisplayUrl;
  }

  factory GifStickerPack.fromStoreRow(
    Map<String, dynamic> row, {
    int index = 0,
  }) {
    String pick(List<String> keys, [String fallback = '']) {
      for (final key in keys) {
        final value = '${row[key] ?? ''}'.trim();
        if (value.isNotEmpty && value != 'null') return value;
      }
      return fallback;
    }

    String firstUrl(String raw) {
      for (final item in raw.split(RegExp(r'[,，\s]+'))) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty && trimmed != 'null') {
          return media_url.resolveMediaUrl(trimmed);
        }
      }
      return '';
    }

    List<dynamic> pickItems() {
      for (final key in const ['stickers', 'emoji_items', 'items', 'emojis']) {
        final value = row[key];
        if (value is List) return value;
      }
      return const [];
    }

    final packId = pick([
      'pack_id',
      'emoji_pack_id',
      'package_id',
      'apps_id',
      'id',
    ], 'pack_$index');
    final packName = pick([
      'pack_name',
      'emoji_pack_name',
      'package_name',
      'name',
      'appname',
    ], '表情包');
    final packCover = firstUrl(
      pick([
        'pack_cover',
        'emoji_pack_cover',
        'package_cover_url',
        'package_cover',
        'cover_url',
        'cover_image',
        'cover_image_url',
        'first_image',
        'first_image_url',
        'thumb',
        'thumb_url',
        'thumbnail',
        'thumbnail_url',
        'cover',
        'app_icon',
        'preview_url',
      ]),
    );
    final stickers = <GifSticker>[];
    final items = pickItems();
    for (var i = 0; i < items.length; i++) {
      final raw = items[i];
      if (raw is! Map) continue;
      final stickerRow = Map<String, dynamic>.from(raw);
      stickerRow.putIfAbsent('pack_id', () => packId);
      stickerRow.putIfAbsent('pack_name', () => packName);
      stickerRow.putIfAbsent('pack_cover', () => packCover);
      final sticker = GifSticker.fromStoreRow(stickerRow, index: i);
      if (sticker.url.trim().isNotEmpty) stickers.add(sticker);
    }
    if (stickers.isEmpty) {
      final sticker = GifSticker.fromStoreRow({
        ...row,
        'pack_id': packId,
        'pack_name': packName,
        'pack_cover': packCover,
      }, index: index);
      if (sticker.url.trim().isNotEmpty) stickers.add(sticker);
    }
    final inferredCover = packCover.isNotEmpty
        ? packCover
        : stickers
              .map((item) => item.packDisplayUrl)
              .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    return GifStickerPack(
      id: packId,
      name: packName,
      coverUrl: inferredCover,
      stickers: stickers,
    );
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
    this.gifStickers = const [],
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
  Widget build(BuildContext context) {
    final packs = groupGifStickerPacks(widget.gifStickers);
    final activePack = packs.isEmpty
        ? null
        : packs.firstWhere(
            (item) => item.id == selectedPackId,
            orElse: () => packs.first,
          );
    return Container(
      height: 222,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: BlinStyle.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BlinStyle.hairline(context, .45).color),
      ),
      child: Column(
        children: [
          _panelHeader(packs, activePack),
          const SizedBox(height: 8),
          Expanded(child: tab == 0 ? _emojiGrid() : _gifGrid(packs)),
        ],
      ),
    );
  }

  Widget _panelHeader(List<GifStickerPack> packs, GifStickerPack? activePack) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: 1 + (widget.showGifTab ? packs.length : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          if (index == 0) {
            return _PanelTab(
              label: '表情',
              active: tab == 0,
              onTap: () => _setTab(0),
            );
          }
          final pack = packs[index - 1];
          return _PackThumbButton(
            pack: pack,
            active: tab == 1 && activePack?.id == pack.id,
            enabled: widget.gifEnabled,
            onTap: () => _selectPack(pack.id),
          );
        },
      ),
    );
  }

  void _setTab(int value) {
    if (value == 1 && !widget.showGifTab) return;
    if (tab == value) return;
    setState(() {
      tab = value;
    });
  }

  void _selectPack(String packId) {
    if (!widget.showGifTab || !widget.gifEnabled) return;
    setState(() {
      selectedPackId = packId;
      tab = 1;
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

  Widget _gifGrid(List<GifStickerPack> packs) {
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
    return _stickerGrid(pack.stickers);
  }

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
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    final localAsset = asset.trim();
    Widget child;
    if (url.isNotEmpty) {
      child = Image.network(
        url,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.broken_image_outlined, color: BlinStyle.subtle),
      );
    } else if (localAsset.isNotEmpty) {
      child = Image.asset(
        localAsset,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        fit: BoxFit.contain,
      );
    } else {
      child = const ColoredBox(
        color: BlinStyle.softFill,
        child: Center(
          child: Icon(Icons.emoji_emotions_outlined, color: BlinStyle.subtle),
        ),
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(11), child: child);
  }
}

class _PackThumbButton extends StatelessWidget {
  final GifStickerPack pack;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const _PackThumbButton({
    required this.pack,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(12),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: active
            ? BlinStyle.primary.withValues(alpha: .10)
            : BlinStyle.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? BlinStyle.primary
              : BlinStyle.hairline(context, .55).color,
          width: active ? 1.4 : 1,
        ),
      ),
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: _StickerImage(
          imageUrl: pack.displayUrl,
          asset: pack.coverSticker.asset,
          isNetwork: pack.coverSticker.isNetwork,
        ),
      ),
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
