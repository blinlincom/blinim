import 'package:flutter/material.dart';
import '../models/community.dart';
import 'blin_style.dart';

class PostCard extends StatelessWidget {
  final CommunityPost post;
  final bool featured;
  const PostCard({super.key, required this.post, this.featured = false});

  bool get _hasVideo => post.videoUrl.trim().isNotEmpty || post.videoCover.trim().isNotEmpty;
  bool get _rightThumbLayout => !_hasVideo && post.images.length == 1 && (post.title.length + post.content.length) <= 80;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AuthorLine(post: post, featured: featured),
          const SizedBox(height: 8),
          if (_rightThumbLayout)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _TextBlock(post: post, maxContentLines: 2)),
                const SizedBox(width: 12),
                _Thumb(url: post.images.first, width: 132, height: 96),
              ],
            )
          else ...[
            _TextBlock(post: post, maxContentLines: post.images.isNotEmpty || _hasVideo ? 2 : 4),
            if (_hasVideo) ...[
              const SizedBox(height: 10),
              _VideoPreview(url: post.videoCover.isNotEmpty ? post.videoCover : (post.image ?? '')),
            ] else if (post.images.length == 1) ...[
              const SizedBox(height: 10),
              _Thumb(url: post.images.first, width: double.infinity, height: 178),
            ] else if (post.images.length > 1) ...[
              const SizedBox(height: 10),
              _ImageGrid(images: post.images),
            ],
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              Text(post.time, style: const TextStyle(color: BlinStyle.muted, fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              _Action(icon: Icons.chat_bubble_outline_rounded, text: '${post.comments}'),
              const SizedBox(width: 18),
              _Action(icon: Icons.thumb_up_alt_outlined, text: post.likes == 0 ? '赞' : '${post.likes}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthorLine extends StatelessWidget {
  final CommunityPost post;
  final bool featured;
  const _AuthorLine({required this.post, required this.featured});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFFF1F3F6),
            backgroundImage: post.avatar.startsWith('http') ? NetworkImage(post.avatar) : null,
            child: post.avatar.startsWith('http') ? null : const Icon(Icons.person_rounded, size: 16, color: BlinStyle.muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    post.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: BlinStyle.ink, fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 5),
                _LevelBadge(text: featured ? '6' : '5'),
              ],
            ),
          ),
          const Icon(Icons.more_horiz_rounded, color: BlinStyle.muted, size: 22),
        ],
      );
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
            style: const TextStyle(color: BlinStyle.ink, fontSize: 18, height: 1.28, fontWeight: FontWeight.w900),
          ),
          if (post.content.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              post.content,
              maxLines: maxContentLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF687182), fontSize: 15, height: 1.45, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      );
}

class _VideoPreview extends StatelessWidget {
  final String url;
  const _VideoPreview({required this.url});

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          _Thumb(url: url, width: double.infinity, height: 188),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .86), shape: BoxShape.circle, boxShadow: [BlinStyle.softShadow(.14)]),
            child: const Icon(Icons.play_arrow_rounded, color: BlinStyle.ink, size: 38),
          ),
          Positioned(
            right: 10,
            bottom: 9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .48), borderRadius: BorderRadius.circular(999)),
              child: const Text('视频', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      );
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
            .map((url) => Expanded(child: Padding(padding: EdgeInsets.only(right: url == shown.first ? 6 : 0), child: _Thumb(url: url, width: double.infinity, height: 150))))
            .toList(),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: shown.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 1.18),
      itemBuilder: (_, index) => Stack(
        fit: StackFit.expand,
        children: [
          _Thumb(url: shown[index], width: double.infinity, height: double.infinity),
          if (index == 3 && images.length > 4)
            Container(
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .38), borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Text('+${images.length - 4}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
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
        child: const Icon(Icons.image_not_supported_outlined, color: BlinStyle.muted),
      );
}

class _LevelBadge extends StatelessWidget {
  final String text;
  const _LevelBadge({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(color: BlinStyle.green.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(color: BlinStyle.green, fontSize: 11, fontWeight: FontWeight.w900)),
      );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Action({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 21, color: BlinStyle.muted),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: BlinStyle.muted, fontWeight: FontWeight.w800, fontSize: 14)),
        ],
      );
}
