import 'package:flutter/material.dart';
import '../models/community.dart';
import 'blin_style.dart';

class PostCard extends StatelessWidget {
  final CommunityPost post;
  final bool featured;
  const PostCard({super.key, required this.post, this.featured = false});

  @override
  Widget build(BuildContext context) => SoftCard(
    radius: 28,
    margin: EdgeInsets.zero,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 23,
              backgroundImage: NetworkImage(post.avatar),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          post.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: BlinStyle.ink,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (featured) const _MiniBadge(text: '推荐'),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${post.time} · 社区动态',
                    style: const TextStyle(
                      color: BlinStyle.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: BlinStyle.cyan.withValues(alpha: .20),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '+ 欣赏',
                style: TextStyle(
                  color: BlinStyle.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: const [
            _TopicPill(text: '# 日常'),
            _TopicPill(text: '# 圈子'),
            _TopicPill(text: '# 同城'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          post.title,
          style: const TextStyle(
            color: BlinStyle.ink,
            fontSize: 18,
            height: 1.25,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          post.content,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF46546A),
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (post.image != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: featured ? 1.62 : 1.85,
              child: Image.network(post.image!, fit: BoxFit.cover),
            ),
          ),
        ],
        const SizedBox(height: 13),
        Row(
          children: [
            _Action(icon: Icons.thumb_up_alt_outlined, text: '${post.likes}'),
            const SizedBox(width: 18),
            _Action(
              icon: Icons.chat_bubble_outline_rounded,
              text: '${post.comments}',
            ),
            const SizedBox(width: 18),
            const _Action(icon: Icons.share_outlined, text: '分享'),
            const Spacer(),
            const Icon(Icons.more_horiz_rounded, color: BlinStyle.muted),
          ],
        ),
      ],
    ),
  );
}

class _MiniBadge extends StatelessWidget {
  final String text;
  const _MiniBadge({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      gradient: BlinStyle.brandGradient,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _TopicPill extends StatelessWidget {
  final String text;
  const _TopicPill({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: BlinStyle.green.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: BlinStyle.ink,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
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
      Icon(icon, size: 18, color: BlinStyle.muted),
      const SizedBox(width: 5),
      Text(
        text,
        style: const TextStyle(
          color: BlinStyle.muted,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    ],
  );
}
