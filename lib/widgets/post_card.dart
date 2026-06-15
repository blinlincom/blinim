import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/community.dart';
import 'blin_style.dart';

class PostCard extends StatelessWidget {
  final CommunityPost post;
  final bool featured;
  final VoidCallback? onTap;
  const PostCard({
    super.key,
    required this.post,
    this.featured = false,
    this.onTap,
  });

  bool get _hasVideo =>
      post.videoUrl.trim().isNotEmpty || post.videoCover.trim().isNotEmpty;
  bool get _rightThumbLayout =>
      !_hasVideo &&
      post.images.length == 1 &&
      (post.title.length + post.content.length) <= 72;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: BlinStyle.surface(context),
              borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
              border: Border.all(color: BlinStyle.hairline(context, .82).color),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AuthorLine(post: post, featured: featured),
                const SizedBox(height: 10),
                if (_rightThumbLayout)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _TextBlock(post: post, maxContentLines: 2),
                      ),
                      const SizedBox(width: 12),
                      _Thumb(url: post.images.first, width: 120, height: 92),
                    ],
                  )
                else ...[
                  _TextBlock(
                    post: post,
                    maxContentLines: post.images.isNotEmpty || _hasVideo
                        ? 2
                        : 4,
                  ),
                  if (_hasVideo) ...[
                    const SizedBox(height: 10),
                    _VideoPreview(
                      coverUrl: post.videoCover,
                      videoUrl: post.videoUrl,
                    ),
                  ] else if (post.images.length == 1) ...[
                    const SizedBox(height: 10),
                    _Thumb(
                      url: post.images.first,
                      width: double.infinity,
                      height: 190,
                    ),
                  ] else if (post.images.length > 1) ...[
                    const SizedBox(height: 10),
                    _ImageGrid(images: post.images),
                  ],
                ],
                const SizedBox(height: 12),
                if (post.sectionName.isNotEmpty || post.time.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (post.sectionName.isNotEmpty)
                        _MetaPill(text: post.sectionName),
                      if (post.time.isNotEmpty)
                        _MetaPill(
                          text: post.time,
                          icon: Icons.schedule_rounded,
                          quiet: true,
                        ),
                    ],
                  ),
                const SizedBox(height: 10),
                Divider(color: BlinStyle.hairline(context, .72).color),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Action(
                      icon: Icons.visibility_outlined,
                      text: post.views == 0 ? '看' : '${post.views}',
                    ),
                    const SizedBox(width: 14),
                    _Action(
                      icon: Icons.chat_bubble_outline_rounded,
                      text: '${post.comments}',
                    ),
                    const SizedBox(width: 14),
                    _Action(
                      icon: Icons.thumb_up_alt_outlined,
                      text: post.likes == 0 ? '赞' : '${post.likes}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthorLine extends StatelessWidget {
  final CommunityPost post;
  final bool featured;
  const _AuthorLine({required this.post, required this.featured});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppAvatar(
          imageUrl: post.avatar.startsWith('http') ? post.avatar : '',
          name: post.author,
          size: 38,
          fallbackIcon: Icons.person_outline_rounded,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  post.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 5),
              if (featured) const _LevelBadge(text: '精选'),
            ],
          ),
        ),
        const Icon(Icons.more_horiz_rounded, color: BlinStyle.subtle, size: 24),
      ],
    );
  }
}

class _TextBlock extends StatelessWidget {
  final CommunityPost post;
  final int maxContentLines;
  const _TextBlock({required this.post, required this.maxContentLines});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        post.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      if (post.content.trim().isNotEmpty) ...[
        const SizedBox(height: 5),
        Text(
          post.content,
          maxLines: maxContentLines,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ],
  );
}

class _VideoPreview extends StatefulWidget {
  final String coverUrl;
  final String videoUrl;
  const _VideoPreview({required this.coverUrl, required this.videoUrl});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? controller;
  bool ready = false;

  bool get hasCover => widget.coverUrl.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (!hasCover && widget.videoUrl.trim().startsWith('http')) {
      controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl.trim()))
            ..initialize()
                .then((_) {
                  controller?.pause();
                  if (mounted) setState(() => ready = true);
                })
                .catchError((_) {});
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (hasCover)
            _Thumb(url: widget.coverUrl, width: double.infinity, height: 188)
          else if (ready && player != null)
            SizedBox(
              width: double.infinity,
              height: 188,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: player.value.size.width,
                  height: player.value.size.height,
                  child: VideoPlayer(player),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: 188,
              decoration: const BoxDecoration(color: Color(0xFFEDEFF3)),
              alignment: Alignment.center,
              child: const Icon(
                Icons.movie_creation_outlined,
                color: BlinStyle.muted,
                size: 34,
              ),
            ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .26),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          Positioned(
            right: 10,
            bottom: 9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .48),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '视频',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<String> images;
  const _ImageGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    final shown = images.take(4).toList();
    if (shown.length == 2) {
      return Row(
        children: shown
            .map(
              (url) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: url == shown.first ? 6 : 0),
                  child: _Thumb(url: url, width: double.infinity, height: 150),
                ),
              ),
            )
            .toList(),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: shown.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.18,
      ),
      itemBuilder: (_, index) => Stack(
        fit: StackFit.expand,
        children: [
          _Thumb(
            url: shown[index],
            width: double.infinity,
            height: double.infinity,
          ),
          if (index == 3 && images.length > 4)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .38),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                '+${images.length - 4}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  const _Thumb({required this.url, required this.width, required this.height});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: url.trim().isEmpty
        ? _fallback
        : Image.network(
            url,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback,
          ),
  );

  Widget get _fallback => Container(
    width: width,
    height: height,
    color: const Color(0xFFF2F4F7),
    child: const Icon(
      Icons.image_not_supported_outlined,
      color: BlinStyle.muted,
    ),
  );
}

class _LevelBadge extends StatelessWidget {
  final String text;
  const _LevelBadge({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: BlinStyle.success.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: BlinStyle.success,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class _MetaPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool quiet;
  const _MetaPill({required this.text, this.icon, this.quiet = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: quiet
          ? BlinStyle.iconSurface(context)
          : BlinStyle.primary.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 13,
            color: quiet ? BlinStyle.subtle : BlinStyle.primary,
          ),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: quiet ? BlinStyle.subtle : BlinStyle.primary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Action({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: BlinStyle.subtle),
      const SizedBox(width: 5),
      Text(
        text,
        style: const TextStyle(
          color: BlinStyle.muted,
          fontWeight: FontWeight.w400,
          fontSize: 14,
        ),
      ),
    ],
  );
}
