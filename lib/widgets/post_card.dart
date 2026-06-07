import 'package:flutter/material.dart';
import '../models/community.dart';
import 'blin_style.dart';

class PostCard extends StatelessWidget {
  final CommunityPost post;
  final bool featured;
  const PostCard({super.key, required this.post, this.featured = false});

  bool get _hasImage => post.image != null && post.image!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final compactImage = _hasImage && post.content.length < 90;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(radius: 14, backgroundImage: NetworkImage(post.avatar)),
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
                    if (featured) const SizedBox(width: 5),
                    if (featured) const _LevelBadge(text: '6'),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz_rounded, color: BlinStyle.muted, size: 22),
            ],
          ),
          const SizedBox(height: 8),
          if (compactImage)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _TextBlock(post: post, maxContentLines: 2)),
                const SizedBox(width: 12),
                _Thumb(url: post.image!, width: 132, height: 96),
              ],
            )
          else ...[
            _TextBlock(post: post, maxContentLines: _hasImage ? 2 : 4),
            if (_hasImage) ...[
              const SizedBox(height: 9),
              _Thumb(url: post.image!, width: double.infinity, height: 178),
            ],
          ],
          const SizedBox(height: 10),
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

class _Thumb extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  const _Thumb({required this.url, required this.width, required this.height});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: width,
            height: height,
            color: const Color(0xFFF2F4F7),
            child: const Icon(Icons.image_not_supported_outlined, color: BlinStyle.muted),
          ),
        ),
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
